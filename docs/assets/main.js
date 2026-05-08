document.addEventListener('DOMContentLoaded', () => {
    const header = document.querySelector('.sticky-header');
    
    window.addEventListener('scroll', () => {
        if (window.scrollY > 400) {
            header.classList.add('visible');
        } else {
            header.classList.remove('visible');
        }
    });
});
