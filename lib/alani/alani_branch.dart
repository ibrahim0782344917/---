import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';

/// Store-only map: never show arbitrary Baghdad merchants as Al-Ani branches.
class AlAniBranchPage extends StatefulWidget {
  const AlAniBranchPage({super.key});
  @override State<AlAniBranchPage> createState()=>_AlAniBranchPageState();
}
class _AlAniBranchPageState extends State<AlAniBranchPage> {
  static const mapsApproved=bool.fromEnvironment(
    'ALANI_GOOGLE_MAPS_APPROVED',defaultValue:false);
  late final Future<MarketplaceStore?> _branch;
  @override
  void initState() {
    super.initState();
    _branch=_readBranch();
  }

  Future<MarketplaceStore?> _readBranch() async {
    if(!MarketplaceBackend.configured)return null;
    final shops=await MarketplaceBackend.approvedStores();
    for(final store in shops) {
      if(store.id==AlAniSettings.storeId)return store;
    }
    return null;
  }

  Future<void> _directions(MarketplaceStore store) async {
    if(store.latitude==null||store.longitude==null)return;
    final uri=Uri.https('www.google.com','/maps/dir/',{
      'api':'1',
      'destination':store.latitude.toString()+','+store.longitude.toString()
    });
    if(!await launchUrl(uri,mode:LaunchMode.externalApplication)&&mounted){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('تعذر فتح الاتجاهات على الخرائط.')));
    }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('فرع السيد إبراهيم العاني')),
    body:FutureBuilder<MarketplaceStore?>(
      future:_branch,builder:(context,snapshot){
        if(snapshot.connectionState!=ConnectionState.done){
          return const Center(child:CircularProgressIndicator());
        }
        if(snapshot.hasError)return const Center(
          child:Text('تعذر قراءة بيانات الفرع. تحقق من اتصال الإنترنت.'));
        final store=snapshot.data;
        if(store==null)return const Center(child:Padding(
          padding:EdgeInsets.all(24),
          child:Text('لم يتم العثور على فرع معتمد تابع للسيد إبراهيم العاني. '
            'لن نعرض فروعاً أو مواقع عشوائية.',
            textAlign:TextAlign.center)));
        final lat=store.latitude,long=store.longitude;
        final hasPoint=lat!=null&&long!=null &&
          lat>=-90&&lat<=90&&long>=-180&&long<=180;
        return ListView(padding:const EdgeInsets.all(16),children:[
          Card(color:const Color(0xFFE7F9EE),child:Padding(
            padding:const EdgeInsets.all(17),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(store.name,style:const TextStyle(
                fontSize:22,fontWeight:FontWeight.w900)),
              const SizedBox(height:8),
              Text(store.area),
              const SizedBox(height:7),
              const Text('هذه الصفحة مخصصة للفرع المعتمد فقط.'),
            ]),
          )),
          const SizedBox(height:13),
          if(!hasPoint)const Card(child:Padding(
            padding:EdgeInsets.all(20),
            child:Text('موقع الفرع الدقيق لم يُعتمد بعد في البيانات؛ '
              'لا يمكن عرض دبوس أو اتجاهات غير صحيحة.'))),
          if(hasPoint&&mapsApproved)SizedBox(
            height:320,
            child:ClipRRect(
              borderRadius:BorderRadius.circular(18),
              child:GoogleMap(
                initialCameraPosition:CameraPosition(
                  target:LatLng(lat,long),zoom:15),
                markers:{
                  Marker(markerId:const MarkerId('alani-approved-branch'),
                    position:LatLng(lat,long),infoWindow:InfoWindow(
                      title:store.name)),
                },
                zoomControlsEnabled:true,
                myLocationEnabled:false,
                mapToolbarEnabled:false,
              ),
            ),
          ),
          if(hasPoint&&!mapsApproved)const Card(child:Padding(
            padding:EdgeInsets.all(18),
            child:Text('الخريطة المدمجة غير مفعلة في هذا البناء، '
              'لكن يمكنك فتح الاتجاهات الخارجية إلى الفرع المعتمد.'))),
          if(hasPoint)Padding(
            padding:const EdgeInsets.only(top:16),
            child:FilledButton.icon(
              onPressed:()=>_directions(store),
              icon:const Icon(Icons.directions_outlined),
              label:const Text('الاتجاهات إلى الفرع المعتمد'),
            ),
          ),
        ]);
      },
    ),
  );
}