const trigger=document.getElementById('menu-trigger');
const panel=document.getElementById('main-side-menu');
const overlay=document.getElementById('main-menu-overlay');
const closer=document.getElementById('menu-close');
function toggleStoreMenu(open){
  if(!trigger||!panel||!overlay||!closer)return;
  panel.classList.toggle('open',open);
  panel.setAttribute('aria-hidden',String(!open));
  trigger.setAttribute('aria-expanded',String(open));
  overlay.hidden=!open;
  document.body.classList.toggle('menu-open',open);
  if(open)closer.focus();else trigger.focus();
}
trigger?.addEventListener('click',()=>toggleStoreMenu(true));
closer?.addEventListener('click',()=>toggleStoreMenu(false));
overlay?.addEventListener('click',()=>toggleStoreMenu(false));
document.addEventListener('keydown',e=>{
  if(e.key==='Escape'&&panel?.classList.contains('open'))toggleStoreMenu(false);
});
