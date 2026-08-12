(function () {
    function getPreferredTheme() {
        const savedTheme = localStorage.getItem('theme');
        if (savedTheme === 'dark' || savedTheme === 'light') {
            return savedTheme;
        }
        return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    }

    function applyTheme(theme) {
        document.documentElement.setAttribute('data-theme', theme);
    }

    // Apply theme immediately to prevent FOUC (Flash of Unstyled Content)
    const initialTheme = getPreferredTheme();
    applyTheme(initialTheme);

    document.addEventListener('DOMContentLoaded', () => {
        const header = document.querySelector('.sticky-header');

        if (header) {
            window.addEventListener('scroll', () => {
                if (window.scrollY > 400) {
                    header.classList.add('visible');
                } else {
                    header.classList.remove('visible');
                }
            });
        }

        // Attach event listeners to all theme toggle buttons
        const toggleBtns = document.querySelectorAll('.theme-toggle-btn');
        toggleBtns.forEach(btn => {
            btn.addEventListener('click', () => {
                const currentTheme = document.documentElement.getAttribute('data-theme') || 'light';
                const nextTheme = currentTheme === 'dark' ? 'light' : 'dark';
                applyTheme(nextTheme);
                localStorage.setItem('theme', nextTheme);
            });
        });

        // Listen for OS theme preference changes
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
            if (!localStorage.getItem('theme')) {
                applyTheme(e.matches ? 'dark' : 'light');
            }
        });
    });
})();

