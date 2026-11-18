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
  final sample=<String>[];

  Future<void> choose() async {
    if(selecting)return;
    setState(()=>selecting=true);
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
      var bad=0,dups=0,sum=0;
      final aliases=<String>[];
      for(final row in values){
        if(row.length!=LegacyCustomerCsv.columns.length){
          bad++;continue;
        }
        final mobile=row[2].trim();
        final orderCount=int.tryParse(row[4]);
        if(row[1].trim().isEmpty ||
            !LegacyCustomerCsv.isIraqiMobile(mobile) ||
            orderCount==null||orderCount<0){
          bad++;continue;
        }
        if(!phones.add(mobile)){dups++;continue;}
        sum+=orderCount;
        if(aliases.length<5){
          final label=row[1].trim();
          aliases.add(label.length>55?label.substring(0,55):label);
        }
      }
      if(!mounted)return;
      setState((){
        fileName=picked.name;
        total=values.length;
        invalid=bad;
        duplicates=dups;
        orders=sum;
        sample..clear()..addAll(aliases);
        error=null;
      });
    }catch(e){
      if(mounted)setState((){
        error=e is FormatException?e.message:'تعذر قراءة CSV. تأكد من صيغة الملف.';
        total=null;
        invalid=null;
        duplicates=null;
        orders=null;
        sample.clear();
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
            const Text('الاستيراد المباشر مغلق للحماية',
              style:TextStyle(fontWeight:FontWeight.w900)),
            const SizedBox(height:8),
            const Text('يمكن مراجعة ملف CSV على الهاتف الآن. '
              'حفظ السجلات في الخادم يتطلب جدولاً خاصاً، '
              'نسخة احتياطية، صلاحيات المالك واختبار عدم التكرار. '
              'لن ننشئ حسابات للزبائن دون إذنهم.'),
          ]),
        )),
      const SizedBox(height:14),
      FilledButton.icon(
        onPressed:selecting?null:choose,
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
        metric('غير مطابقة أو ناقصة',invalid.toString(),
          Icons.warning_amber_outlined),
        metric('أرقام مكررة داخل الملف',duplicates.toString(),
          Icons.content_copy_outlined),
        metric('الطلبات التاريخية المذكورة',orders.toString(),
          Icons.history_outlined),
        const Padding(padding:EdgeInsets.all(12),
          child:Text('المعاينة محلية فقط؛ لم يتم إرسال أي معلومات '
            'شخصية إلى الخادم من هذه الصفحة.',
            style:TextStyle(fontSize:12,color:Colors.black54))),
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
