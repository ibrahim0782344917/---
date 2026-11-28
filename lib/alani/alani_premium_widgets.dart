import 'package:flutter/material.dart';

/// Presentational components only. No data, authentication or payment logic.
class AlAniSectionBanner extends StatelessWidget {
  const AlAniSectionBanner({super.key,required this.icon,required this.title,
    required this.subtitle,this.detail});
  final IconData icon;
  final String title,subtitle;
  final String? detail;
  @override
  Widget build(BuildContext context)=>Container(
    width:double.infinity,
    padding:const EdgeInsets.all(18),
    decoration:BoxDecoration(
      gradient:const LinearGradient(colors:[Color(0xFF17372B),Color(0xFF17583D)],
        begin:AlignmentDirectional.topStart,end:AlignmentDirectional.bottomEnd),
      borderRadius:BorderRadius.circular(24)),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
        Container(width:48,height:48,decoration:BoxDecoration(
          color:const Color(0xFFDFCA92),borderRadius:BorderRadius.circular(16)),
          child:Icon(icon,color:const Color(0xFF17372B),size:26)),
        const SizedBox(width:12),
        Expanded(child:Text(title,style:const TextStyle(color:Colors.white,
          fontWeight:FontWeight.w800,fontSize:21,height:1.3))),
      ]),
      const SizedBox(height:12),
      Text(subtitle,style:const TextStyle(color:Color(0xFFD9E8DE),height:1.5,fontSize:14)),
      if(detail!=null)...[
        const SizedBox(height:8),
        Text(detail!,style:const TextStyle(color:Color(0xFFF3DC9E),fontWeight:FontWeight.w800,fontSize:25)),
      ],
    ]));
}
class AlAniSectionTitle extends StatelessWidget {
  const AlAniSectionTitle(this.title,{super.key,this.icon});
  final String title;
  final IconData? icon;
  @override
  Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.fromLTRB(4,10,4,8),
    child:Row(children:[
      if(icon!=null)...[Icon(icon,color:Theme.of(context).colorScheme.primary,size:21),const SizedBox(width:8)],
      Expanded(child:Text(title,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800))),
    ]));
}
class AlAniEmptyState extends StatelessWidget {
  const AlAniEmptyState({super.key,required this.icon,required this.message,this.action});
  final IconData icon;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    return Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(
      mainAxisSize:MainAxisSize.min,children:[
        CircleAvatar(radius:27,backgroundColor:scheme.primaryContainer,
          child:Icon(icon,size:28,color:scheme.onPrimaryContainer)),
        const SizedBox(height:12),
        Text(message,textAlign:TextAlign.center,style:Theme.of(context).textTheme.bodyMedium),
        if(action!=null)...[const SizedBox(height:8),action!],
      ])));
  }
}
