import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// TEST receipt only. Invoice data comes from the authorized server list.
class AlAniPosPdf {
  static Future<Uint8List> build(Map<String,dynamic> invoice,PdfPageFormat format)async{
    final arabic=await PdfGoogleFonts.notoSansArabicRegular();
    final latin=await PdfGoogleFonts.notoSansRegular();
    final rows=(invoice['lines'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    int returned=0;
    for(final l in rows){returned+=(l['returned_qty'] as num).toInt()*(l['unit_price_iqd'] as num).toInt();}
    final total=(invoice['total_iqd'] as num).toInt();
    final doc=pw.Document();
    final style=pw.TextStyle(font:arabic,fontFallback:[latin],fontSize:11);
    pw.Widget line(String value)=>pw.Padding(padding:const pw.EdgeInsets.symmetric(vertical:4),child:pw.Text(value,textDirection:pw.TextDirection.rtl,style:style));
    doc.addPage(pw.MultiPage(pageFormat:format,margin:const pw.EdgeInsets.all(24),
      build:(_)=>[
        line('السيد إبراهيم العاني'),
        line('إيصال اختبار TEST - غير ضريبي'),
        line('رقم الفاتورة:'),
        pw.Text(invoice['id'].toString(),style:pw.TextStyle(font:latin,fontSize:9)),
        pw.Text(invoice['created_at'].toString(),style:pw.TextStyle(font:latin,fontSize:9)),
        pw.Divider(),
        for(final l in rows)...[
          line(l['name'].toString()),
          line('الكمية: ${l['quantity']} | سعر الوحدة: ${l['unit_price_iqd']} د.ع'),
          line('المرتجع: ${l['returned_qty']}'),
          pw.Divider(),
        ],
        line('إجمالي الفاتورة: $total د.ع'),
        line('قيمة المرتجعات المسجلة: $returned د.ع'),
        line('الصافي: ${total-returned} د.ع'),
        line('هذا الإيصال ليس إثبات دفع حقيقي.'),
      ]));
    return doc.save();
  }
  static Future<void> printReceipt(Map<String,dynamic> invoice)async{
    await Printing.layoutPdf(name:'alani-test-receipt',onLayout:(format)=>build(invoice,format));
  }
  static Future<void> shareReceipt(Map<String,dynamic> invoice)async{
    await Printing.sharePdf(bytes:await build(invoice,PdfPageFormat.a4),filename:'alani-test-receipt.pdf');
  }
}
