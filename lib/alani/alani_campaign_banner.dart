import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/backend/marketplace_backend.dart';

/// Pure UTC start-inclusive, end-exclusive visibility test.
class AlAniCampaignWindow {
  const AlAniCampaignWindow._();
  static bool visible(DateTime start,DateTime end,DateTime now) =>
      !now.toUtc().isBefore(start.toUtc()) &&
      now.toUtc().isBefore(end.toUtc()) &&
      end.toUtc().isAfter(start.toUtc());
}

class AlAniCampaignBanner extends StatefulWidget {
  const AlAniCampaignBanner({super.key});
  @override
  State<AlAniCampaignBanner> createState()=>_AlAniCampaignBannerState();
}
class _AlAniCampaignBannerState extends State<AlAniCampaignBanner> {
  static const enabled=bool.fromEnvironment(
    'SHITREED_CAMPAIGNS_ENABLED',defaultValue:false);
  late Future<List<Map<String,dynamic>>> _campaigns;
  Timer? _clock;
  int _page=0;
  final _controller=PageController();

  @override
  void initState(){
    super.initState();
    _campaigns=enabled?_fetch():Future.value(<Map<String,dynamic>>[]);
    if(enabled) {
      _clock=Timer.periodic(const Duration(seconds:30),(_){
        if(mounted)setState((){/* Expiry checked against current UTC */});
      });
    }
  }

  Future<List<Map<String,dynamic>>> _fetch() async {
    if(!MarketplaceBackend.configured)return [];
    try {
      return await Supabase.instance.client
        .from('shitreed_store_campaigns')
        .select('id,title,description,starts_at,ends_at,is_published')
        .eq('store_id',AlAniSettings.storeId)
        .eq('is_published',true)
        .order('starts_at');
    } catch (_) {
      // Table may not yet be enabled. Never substitute fake campaigns.
      return [];
    }
  }

  @override
  void dispose(){
    _clock?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    if(!enabled)return const SizedBox.shrink();
    return FutureBuilder<List<Map<String,dynamic>>>(
      future:_campaigns,builder:(context,snapshot){
        if(snapshot.connectionState!=ConnectionState.done||
            snapshot.hasError)return const SizedBox.shrink();
        final now=DateTime.now().toUtc();
        final active=(snapshot.data??[]).where((row){
          final start=DateTime.tryParse(row['starts_at']?.toString()??'');
          final end=DateTime.tryParse(row['ends_at']?.toString()??'');
          return row['is_published']==true && start!=null && end!=null &&
            AlAniCampaignWindow.visible(start,end,now);
        }).toList();
        if(active.isEmpty)return const SizedBox.shrink();
        if(_page>=active.length)_page=0;
        return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('عروض محدودة الوقت',
            style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
          const SizedBox(height:10),
          SizedBox(height:175,child:PageView.builder(
            controller:_controller,itemCount:active.length,
            onPageChanged:(index)=>setState(()=>_page=index),
            itemBuilder:(context,index){
              final row=active[index];
              final ends=DateTime.tryParse(row['ends_at']?.toString()??'');
              return Container(
                margin:const EdgeInsetsDirectional.only(end:9),
                padding:const EdgeInsets.all(19),
                decoration:BoxDecoration(
                  borderRadius:BorderRadius.circular(19),
                  gradient:const LinearGradient(colors:[
                    Color(0xFF123E2D),Color(0xFF01BE5F)])),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  const Icon(Icons.campaign_outlined,
                    color:Color(0xFFF5D995),size:26),
                  const SizedBox(height:8),
                  Text(row['title']?.toString()??'',
                    maxLines:2,overflow:TextOverflow.ellipsis,
                    style:const TextStyle(color:Colors.white,
                      fontSize:18,fontWeight:FontWeight.w900)),
                  Text(row['description']?.toString()??'',
                    maxLines:2,overflow:TextOverflow.ellipsis,
                    style:const TextStyle(color:Colors.white70,fontSize:12)),
                  const Spacer(),
                  Text(ends==null?'':'ينتهي: '+ends.toLocal().toString().substring(0,16),
                    style:const TextStyle(color:Colors.white70,fontSize:11)),
                ]),
              );
            },
          )),
          if(active.length>1)Padding(
            padding:const EdgeInsets.only(top:9),
            child:Center(child:Text('العرض '+(_page+1).toString()+
              ' من '+active.length.toString(),
              style:const TextStyle(fontSize:11,color:Colors.black54))),
          ),
          const SizedBox(height:12),
        ]);
      },
    );
  }
}