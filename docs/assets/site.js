'use strict';

const track = document.querySelector('.gallery-track');
const controls = document.querySelector('.gallery-controls');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

if (track && controls) {
  controls.hidden = false;
  const buttons = [...controls.querySelectorAll('button')];
  const updateControls = () => {
    buttons[0].disabled = track.scrollLeft < 2;
    buttons[1].disabled = track.scrollLeft >= track.scrollWidth - track.clientWidth - 2;
  };
  buttons.forEach((button) => {
    button.addEventListener('click', () => {
      const item = track.querySelector('.gallery-item');
      const gap = parseFloat(getComputedStyle(track).gap) || 0;
      track.scrollBy({
        left: Number(button.dataset.galleryDirection) * (item.getBoundingClientRect().width + gap),
        behavior: reducedMotion.matches ? 'instant' : 'smooth',
      });
    });
  });
  track.addEventListener('scroll', updateControls, { passive: true });
  window.addEventListener('resize', updateControls);
  updateControls();
}

const lightbox = document.querySelector('.lightbox');
if (lightbox && typeof lightbox.showModal === 'function') {
  const image = lightbox.querySelector('img');
  const closeButton = lightbox.querySelector('button');
  let trigger;
  document.querySelectorAll('.gallery-item').forEach((link) => {
    link.addEventListener('click', (event) => {
      if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      trigger = link;
      image.src = link.href;
      image.alt = link.querySelector('img').alt;
      lightbox.showModal();
      closeButton.focus();
    });
  });
  closeButton.addEventListener('click', () => lightbox.close());
  lightbox.addEventListener('click', (event) => {
    if (event.target !== lightbox) return;
    const bounds = lightbox.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right ||
        event.clientY < bounds.top || event.clientY > bounds.bottom) lightbox.close();
  });
  lightbox.addEventListener('close', () => trigger?.focus({ preventScroll: true }));
}
