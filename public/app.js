'use strict';
const menuButton=document.querySelector('.menu-toggle');const nav=document.querySelector('#navigation');
menuButton.addEventListener('click',()=>{const open=menuButton.getAttribute('aria-expanded')!=='true';menuButton.setAttribute('aria-expanded',String(open));nav.classList.toggle('open',open);});
nav.querySelectorAll('a').forEach(a=>a.addEventListener('click',()=>{nav.classList.remove('open');menuButton.setAttribute('aria-expanded','false');}));
// Progressive motion: content stays visible if animation is unavailable.
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const finePointer = window.matchMedia('(hover: hover) and (pointer: fine)');
const activeMotion = new Set();
function animateElement(element, frames, options) {
  if (reducedMotion.matches || !element.animate) return;
  const animation = element.animate(frames, options);
  activeMotion.add(animation);
  animation.finished.catch(() => {}).finally(() => activeMotion.delete(animation));
}
const imageStages = [];
document.querySelectorAll('.hero-art > img, .brand-story > img, .club-gallery figure > img').forEach(img => {
  const stage = document.createElement('div');
  stage.className = 'image-stage';
  img.before(stage); stage.append(img); imageStages.push(stage);
});
const heroImage = document.querySelector('.hero-art .image-stage');
if (heroImage) {
  let frame = 0;
  heroImage.addEventListener('pointermove', event => {
    if (reducedMotion.matches || !finePointer.matches || event.pointerType === 'touch') return;
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(() => {
      const bounds = heroImage.getBoundingClientRect();
      const x = (event.clientX - bounds.left) / bounds.width - .5;
      const y = (event.clientY - bounds.top) / bounds.height - .5;
      heroImage.style.setProperty('--tilt-x', `${-y * 3}deg`);
      heroImage.style.setProperty('--tilt-y', `${x * 3}deg`);
    });
  });
  const resetTilt = () => {cancelAnimationFrame(frame);heroImage.style.setProperty('--tilt-x','0deg');heroImage.style.setProperty('--tilt-y','0deg');};
  heroImage.addEventListener('pointerleave', resetTilt);
  heroImage.addEventListener('pointercancel', resetTilt);
  reducedMotion.addEventListener('change', resetTilt);
}
if (!reducedMotion.matches) {
  document.querySelectorAll('.hero-copy > *').forEach((element,index) => {
    animateElement(element,[{opacity:0,transform:'translateY(22px)'},{opacity:1,transform:'translateY(0)'}],{duration:900,delay:index*85,easing:'cubic-bezier(.2,.7,.2,1)',fill:'backwards'});
  });
  if (heroImage) animateElement(heroImage,[{opacity:0,clipPath:'inset(7% 0 7% 0)',transform:'translateY(25px)'},{opacity:1,clipPath:'inset(0% 0 0% 0)',transform:'translateY(0)'}],{duration:1400,delay:130,easing:'cubic-bezier(.2,.7,.2,1)',fill:'backwards'});
}
if ('IntersectionObserver' in window) {
  const revealObserver = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      revealObserver.unobserve(entry.target);
      animateElement(entry.target,[{opacity:0,transform:'translateY(24px)'},{opacity:1,transform:'translateY(0)'}],{duration:850,easing:'cubic-bezier(.2,.7,.2,1)'});
    });
  },{threshold:.12});
  document.querySelectorAll('.card, .brand-story, .how-panel, .club-gallery figure, .about > div').forEach(element => revealObserver.observe(element));
}
reducedMotion.addEventListener('change', () => {if(reducedMotion.matches){activeMotion.forEach(animation=>animation.cancel());activeMotion.clear();}});
