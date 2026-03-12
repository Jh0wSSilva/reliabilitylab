document.addEventListener('DOMContentLoaded', () => {
  // Initialize Icons
  if (typeof lucide !== 'undefined') {
    lucide.createIcons();
  }

  // Highlight.js
  if (typeof hljs !== 'undefined') {
    hljs.highlightAll();
  }

  // Mobile sidebar toggle
  const mobileBtn = document.getElementById('mobileMenuBtn');
  const sidebar = document.getElementById('sidebar');
  if (mobileBtn && sidebar) {
    mobileBtn.addEventListener('click', () => sidebar.classList.toggle('mobile-open'));
    // Close sidebar when clicking outside on mobile
    document.addEventListener('click', (e) => {
      if (sidebar.classList.contains('mobile-open') &&
          !sidebar.contains(e.target) && !mobileBtn.contains(e.target)) {
        sidebar.classList.remove('mobile-open');
      }
    });
  }

  // Theme Toggle
  const themeBtn = document.getElementById('themeToggle');
  const htmlEl = document.documentElement;
  
  // check localstorage
  const savedTheme = localStorage.getItem('theme');
  if (savedTheme) {
      htmlEl.setAttribute('data-theme', savedTheme);
      if (document.getElementById('themeIcon')) {
        document.getElementById('themeIcon').setAttribute('data-lucide', savedTheme === 'dark' ? 'sun' : 'moon');
        lucide.createIcons();
      }
  }

  if (themeBtn) {
    themeBtn.addEventListener('click', () => {
      const next = htmlEl.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      htmlEl.setAttribute('data-theme', next);
      localStorage.setItem('theme', next);
      document.getElementById('themeIcon').setAttribute('data-lucide', next === 'dark' ? 'sun' : 'moon');
      lucide.createIcons();
    });
  }

  // Copy Buttons
  document.querySelectorAll('.copy-btn').forEach(btn => {
    btn.addEventListener('click', e => {
      const code = e.target.closest('.code-wrapper').querySelector('code').innerText;
      navigator.clipboard.writeText(code);
      btn.innerHTML = '<i data-lucide="check" size="14"></i> Copied!';
      lucide.createIcons();
      setTimeout(() => {
          btn.innerHTML = '<i data-lucide="copy" size="14"></i> Copy';
          lucide.createIcons();
      }, 2000);
    });
  });

  // Global Search Modal
  const mOverlay = document.getElementById('searchModal');
  const sBtn = document.getElementById('searchBtn');
  const sInput = document.getElementById('searchInput');
  const sResults = document.getElementById('searchResults');

  function openSearch() {
    if (mOverlay) {
      mOverlay.classList.add('active');
      sInput.focus();
    }
  }

  function closeSearch() {
    if (mOverlay) {
      mOverlay.classList.remove('active');
      sInput.value = '';
      sResults.innerHTML = '';
    }
  }

  if(sBtn) sBtn.addEventListener('click', openSearch);
  
  if(mOverlay) {
      mOverlay.addEventListener('click', (e) => {
        if(e.target === mOverlay) closeSearch();
      });
  }

  // Ctrl+K shortcut
  document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
      e.preventDefault();
      openSearch();
    }
    if (e.key === 'Escape') {
      closeSearch();
    }
  });

  // Search Logic (debounce)
  let timer;
  if(sInput) {
      sInput.addEventListener('input', (e) => {
        clearTimeout(timer);
        timer = setTimeout(async () => {
            const q = e.target.value;
            if (q.length < 2) {
                sResults.innerHTML = '';
                return;
            }
            try {
                const res = await fetch('/api/search?q=' + encodeURIComponent(q));
                const data = await res.json();
                sResults.innerHTML = data.map(i => `
                    <a href="${i.slug}" class="search-result-item">
                        <h4>${i.title}</h4>
                        <div style="font-size: 0.8rem; color: var(--accent-blue)">${i.category}</div>
                        <div style="font-size: 0.9rem; margin-top: 0.5rem">${i.excerpt}</div>
                    </a>
                `).join('');
            } catch (err) {
                console.error("Search failed", err);
            }
        }, 300);
      });
  }
});
