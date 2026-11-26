import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// A local file preview only. No sensitive contact data is uploaded or stored.
/// Import requires a private staging-tested server API with an audit trail.
class LegacyCustomerCsv {
  static const columns=<String>[
    'source_serial','recipient_name','phone_primary','phone_secondary',
    'historical_order_count','governorate','district','address_details',
    'goods_type','source_row'
  ];

  static List<List<String>> parse(String csv) {
    final result=<List<String>>[];
    var row=<String>[];
    var cell=StringBuffer();
    var quoted=false;
    for(var i=0;i<csv.length;i++){
      final ch=csv[i];
      if(ch=='"'){
        if(quoted&&i+1<csv.length&&csv[i+1]=='"'){
          cell.write('"');i++;
        }else{quoted=!quoted;}
      }else if(ch==','&&!quoted){
        row.add(cell.toString());cell=StringBuffer();
      }else if((ch=='\n'||ch=='\r')&&!quoted){
        row.add(cell.toString());
        if(row.any((part)=>part.isNotEmpty))result.add(row);
        row=<String>[];cell=StringBuffer();
        if(ch=='\r'&&i+1<csv.length&&csv[i+1]=='\n')i++;
      }else{
        cell.write(ch);
      }
    }
    if(quoted)throw const FormatException('CSV contains an unclosed quote');
    row.add(cell.toString());
    if(row.any((part)=>part.isNotEmpty))result.add(row);
    return result;
  }

  static bool matchesHeader(List<String> fields)=>
    fields.length==columns.length &&
    List.generate(columns.length,(i)=>fields[i]==columns[i])
      .every((v)=>v);

  static bool isIraqiMobile(String s)=>
    RegExp(r'^07[3-9][0-9]{8}$').hasMatch(s);
}

class AlAniLegacyCustomersImportPage extends StatefulWidget {
  const AlAniLegacyCustomersImportPage({super.key});

  @override
  State<AlAniLegacyCustomersImportPage> createState() =>
    _AlAniLegacyCustomersImportPageState();
}

class _AlAniLegacyCustomersImportPageState
  extends State<AlAniLegacyCustomersImportPage> {
  int? total,invalid,duplicates,orders;
  String? error,fileName;
  bool selecting=false;
  bool importing=false;
  int processed=0;
  String? importStatus;
  final _readyRows=<Map<String,dynamic>>[];
  static const _testOnly=String.fromEnvironment('SUPABASE_URL') ==
    'https://tgvdwotbrnhcoykuxdpr.supabase.co';

  Future<void> commitImport() async {
    if (!_testOnly || importing || selecting || _readyRows.isEmpty ||
        invalid!=0 || duplicates!=0) return;
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('استيراد خاص إلى TEST'),
      content:Text('حفظ ${_readyRows.length} سجل زبون خاص دون إنشاء حسابات أو إرسال رسائل. يلزم حساب مدير عام وتحقق بخطوتين. هل تؤكد؟'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('تأكيد الاستيراد')),
      ],
    ));
    if (confirmed!=true || !mounted) return;
    final db=Supabase.instance.client;
    final user=db.auth.currentUser?.id;
    if(user==null)return;
    setState((){importing=true;processed=0;importStatus=null;});
    try{
      for(var start=0;start<_readyRows.length;start+=100){
        if(!mounted || db.auth.currentUser?.id!=user)break;
        final end=(start+100>_readyRows.length)?_readyRows.length:start+100;
        final response=await db.rpc('alani_commit_legacy_import_test',params:{
          'p_rows':_readyRows.sublist(start,end),
        });
        if(response is! Map || response['rows']!=end-start)throw StateError('Invalid server result');
        if(!mounted)return;
        setState(()=>processed=end);
      }
      if(mounted)setState(()=>importStatus=processed==_readyRows.length?
        'اكتمل حفظ السجلات والتحقق منها.':'توقف الاستيراد. يمكن إعادة المحاولة دون تكرار.');
    }catch(_){
      if(mounted)setState(()=>importStatus='توقف الحفظ. تحقق من صلاحية المدير العام والتحقق بخطوتين وصحة الملف. يمكنك إعادة المحاولة دون تكرار.');
    }finally{
      if(mounted)setState(()=>importing=false);
    }
  }


  Future<void> choose() async {
    if(selecting||importing)return;
    setState((){selecting=true;_readyRows.clear();total=null;importStatus=null;processed=0;});
    try{
      final picked=await FilePicker.pickFile(
        type:FileType.custom,allowedExtensions:['csv']);
      if(picked==null)return;
      // Protect memory usage from unexpected files.
      if((await picked.length() ?? 0)>7*1024*1024)throw const FormatException(
        'الملف أكبر من 7 ميغابايت، قسّمه إلى دفعات أصغر.');
      final bytes=await picked.readAsBytes();
      final source=utf8.decode(bytes,allowMalformed:false)
        .replaceFirst('\uFEFF','');
      final parsed=LegacyCustomerCsv.parse(source);
      if(parsed.isEmpty||!LegacyCustomerCsv.matchesHeader(parsed.first)){
        throw const FormatException(
          'الأعمدة لا تطابق ملف CSV المجهز لزبائن السيد إبراهيم العاني.');
      }
      final values=parsed.skip(1).toList();
      if(values.length>10000)throw const FormatException(
        'الحد الأعلى للمعاينة 10,000 سجل.');
      final phones=<String>{};
      final serials=<int>{};
      final sourceRows=<int>{};
      final ready=<Map<String,dynamic>>[];
      var bad=0,dups=0,sum=0;
      for(final row in values){
        if(row.length!=LegacyCustomerCsv.columns.length){
          bad++;continue;
        }
        final mobile=row[2].trim();
        final orderCount=int.tryParse(row[4]);
        final serial=int.tryParse(row[0]);
        final sourceRow=int.tryParse(row[9]);
        if(row[1].trim().isEmpty ||
            !LegacyCustomerCsv.isIraqiMobile(mobile) ||
            orderCount==null||orderCount<0||serial==null||serial<=0||
            sourceRow==null||sourceRow<=0||row[1].trim().length>160||
            (row[3].isNotEmpty&&!RegExp(r'^07[0-9]{9}$').hasMatch(row[3]))||
            row[5].length>=150||row[6].length>=200||row[7].length>=1500||row[8].length>=1000){
          bad++;continue;
        }
        if(phones.contains(mobile)||serials.contains(serial)||sourceRows.contains(sourceRow)){dups++;continue;}
        phones.add(mobile);serials.add(serial);sourceRows.add(sourceRow);
        ready.add({'source_serial':serial,'recipient_name':row[1].trim(),
          'phone_primary':mobile,'phone_secondary':row[3], 'historical_order_count':orderCount,
          'governorate':row[5],'district':row[6],'address_details':row[7],
          'goods_type':row[8],'source_row':sourceRow});
        sum+=orderCount;
      }
      if(!mounted)return;
      setState((){
        fileName=picked.name;
        total=values.length;
        invalid=bad;
        duplicates=dups;
        orders=sum;
        _readyRows..clear()..addAll(ready);
        error=null;
      });
    }catch(e){
      if(mounted)setState((){
        error=e is FormatException?e.message:'تعذر قراءة CSV. تأكد من صيغة الملف.';
        total=null;
        invalid=null;
        duplicates=null;
        orders=null;
      });
    }finally{
      if(mounted)setState(()=>selecting=false);
    }
  }

  Widget metric(String title,String value,IconData icon)=>Card(
    child:ListTile(
      leading:Icon(icon,color:const Color(0xFF0E8E56)),
      title:Text(title),
      trailing:Text(value,style:const TextStyle(
        fontWeight:FontWeight.w900,fontSize:17)),
    ),
  );

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('زبائن السيد إبراهيم العاني القدامى')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('إدارة استيراد الزبائن السابقين',
        style:TextStyle(fontSize:23,fontWeight:FontWeight.w900,
          color:Color(0xFF143F2D))),
      const SizedBox(height:10),
      const Text('هذه سجلات زبائن سابقين وليست حسابات تسجيل دخول. '
        'لا تظهر أرقامهم وعناوينهم للمستخدمين، '
        'ولا ننشئ منها طلبات أو فواتير تلقائياً.',
        style:TextStyle(height:1.6)),
      const SizedBox(height:15),
      Card(color:const Color(0xFFFFF2DC),
        child:Padding(padding:const EdgeInsets.all(16),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('الاستيراد الخاص محمي بصلاحيات المدير العام',
              style:TextStyle(fontWeight:FontWeight.w900)),
            const SizedBox(height:8),
            const Text('يمكن مراجعة ملف CSV على الهاتف ثم حفظه على TEST فقط. '
              'حفظ السجلات في الخادم يتطلب تحققاً بخطوتين، '
              'وصلاحيات المدير العام. الخادم يمنع التكرار. '
              'لن ننشئ حسابات للزبائن دون إذنهم.'),
          ]),
        )),
      const SizedBox(height:14),
      FilledButton.icon(
        onPressed:selecting||importing?null:choose,
        icon:const Icon(Icons.upload_file_outlined),
        label:Text(selecting?'جارٍ قراءة الملف…':'اختيار ملف الزبائن CSV للمعاينة'),
      ),
      if(error!=null)Card(child:Padding(padding:const EdgeInsets.all(15),
        child:Text(error!,style:const TextStyle(color:Colors.red)))),
      if(total!=null) ...[
        const SizedBox(height:14),
        Text(fileName??'',style:const TextStyle(
          fontWeight:FontWeight.w800,fontSize:14)),
        metric('سجلات الملف',total.toString(),Icons.people_outline),
        metric('صالحة مبدئياً', (total!-invalid!-duplicates!).toString(),
          Icons.check_circle_outline),
        metric('غير مطابقة أو ناقصة',invalid.toString(),
          Icons.warning_amber_outlined),
        metric('أرقام مكررة داخل الملف',duplicates.toString(),
          Icons.content_copy_outlined),
        metric('الطلبات التاريخية المذكورة',orders.toString(),
          Icons.history_outlined),
        const Padding(padding:EdgeInsets.all(12),
          child:Text('المعاينة محلية قبل تأكيد الحفظ؛ لا يتم إرسال أي معلومات '
            'شخصية إلا عند تأكيد الاستيراد الخاص.',
            style:TextStyle(fontSize:12,color:Colors.black54))),
      ],
      if(_testOnly && total!=null) ...[
        FilledButton.icon(onPressed:importing||selecting||_readyRows.isEmpty||
          invalid!=0||duplicates!=0?null:commitImport,
          icon:const Icon(Icons.cloud_upload_outlined),
          label:Text(importing?'جارٍ الحفظ: $processed / ${_readyRows.length}':'حفظ السجلات الخاصة على TEST')),
        if(importing) LinearProgressIndicator(value:_readyRows.isEmpty?0:processed/_readyRows.length),
        if(importStatus!=null) Text(importStatus!),
      ],
      const SizedBox(height:13),
      const Text('خطوات الاستيراد الآمن',
        style:TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
      const Text('1. مراجعة قائمة الأخطاء والاتصالات المكررة.\n'
        '2. أخذ نسخة احتياطية لقاعدة بيانات المتجر.\n'
        '3. تجربة الاستيراد في قاعدة منفصلة مع اختبار الصلاحيات.\n'
        '4. تفعيل استيراد آمن بتسجيل كل عملية وإمكانية منع التكرار.\n'
        '5. ربط حساب الزبون الفعلي فقط بعد إثبات ملكية الرقم وموافقته.',
        style:TextStyle(height:1.85)),
    ]),
  );
}
