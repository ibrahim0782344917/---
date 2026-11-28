import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


abstract final class AlAniEvidence {
  static const enabled = bool.fromEnvironment('ALANI_DELIVERY_EVIDENCE_ENABLED') &&
    String.fromEnvironment('SUPABASE_URL')=='https://ltwncrewggdrjevakwpb.supabase.co';
  static const bucket='alani-private-evidence';
  static String path(String kind,String id) {
    if(!RegExp(r'^(delivery|return)$').hasMatch(kind) ||
       !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch(id)) {
      throw ArgumentError('INVALID_EVIDENCE_PATH');
    }
    return '$kind/$id/proof.jpg';
  }
}
class AlAniEvidencePage extends StatefulWidget {
  const AlAniEvidencePage({super.key,required this.kind,required this.id});
  final String kind,id;
  
  @override
  State<AlAniEvidencePage> createState()=>_AlAniEvidencePageState();
}
class _AlAniEvidencePageState extends State<AlAniEvidencePage> with WidgetsBindingObserver {
  SupabaseClient get db=>Supabase.instance.client;
  late final String? actor;
  StreamSubscription<dynamic>? subscription;
  MemoryImage? photo;
  bool busy=false;
  String message='اضغط لعرض الصورة الخاصة.';
  int generation=0;
  bool get sameActor=>actor!=null&&actor==db.auth.currentUser?.id;
  String get path=>AlAniEvidence.path(widget.kind,widget.id);
  @override
  void initState(){
    super.initState();actor=db.auth.currentUser?.id;WidgetsBinding.instance.addObserver(this);
    subscription=db.auth.onAuthStateChange.listen((_){if(mounted&&!sameActor){clearPhoto();setState(()=>message='انتهت جلسة العرض.');}});
  }
  void clearPhoto(){generation++;final old=photo;photo=null;if(old!=null)unawaited(old.evict());}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){if(state!=AppLifecycleState.resumed&&mounted){setState(clearPhoto);}}
  @override
  void dispose(){subscription?.cancel();WidgetsBinding.instance.removeObserver(this);clearPhoto();super.dispose();}
  Future<void> readPhoto()async{
    if(busy||!sameActor||!AlAniEvidence.enabled)return;
    clearPhoto();final g=generation;setState(()=>busy=true);
    try{
      final bytes=await db.storage.from(AlAniEvidence.bucket).download(path);
      if(!mounted||!sameActor||g!=generation)return;
      if(bytes.isEmpty||bytes.length>3145728)throw StateError('INVALID_PHOTO');
      setState((){photo=MemoryImage(bytes);message='صورة خاصة بالطلب؛ ليست إثبات تحصيل نقدي.';});
    }catch(_){if(mounted&&g==generation)setState(()=>message='الصورة غير متاحة أو لا تملك صلاحية عرضها.');}
    finally{if(mounted)setState(()=>busy=false);}
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.kind=='delivery'?'صورة التسليم':'إثبات التلف أو الاسترجاع')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Text(sameActor?message:'انتهت الجلسة.'),
      if(busy)const LinearProgressIndicator(),
      if(sameActor&&photo!=null)Image(image:photo!,fit:BoxFit.contain,errorBuilder:(_,__,___)=>const Text('تعذر عرض الصورة.')),
      FilledButton.icon(onPressed:busy||!sameActor?null:readPhoto,icon:const Icon(Icons.visibility_outlined),label:const Text('عرض الصورة')),
      
    ]),
  );
}
