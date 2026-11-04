// Language selection is kept in the URL; this notice does not need cookies or storage.
(() => {
  'use strict';

  const versions = [...document.querySelectorAll('[data-policy-language]')];
  const choices = [...document.querySelectorAll('[data-language-choice]')];
  const validLanguage = value => value === 'en' || value === 'ms';

  function selectLanguage(language) {
    const selected = validLanguage(language) ? language : 'en';
    versions.forEach(version => {
      version.hidden = version.dataset.policyLanguage !== selected;
    });
    choices.forEach(choice => {
      if (choice.dataset.languageChoice === selected) {
        choice.setAttribute('aria-current', 'true');
      } else {
        choice.removeAttribute('aria-current');
      }
    });
    document.documentElement.lang = selected;
    document.title = selected === 'ms'
      ? 'Notis Privasi | HikerCircle Malaysia'
      : 'Privacy Notice | HikerCircle Malaysia';
    return selected;
  }

  function languageInAddress() {
    const hash = window.location.hash;
    if (hash === '#policy-ms' || hash.startsWith('#ms-')) return 'ms';
    if (hash === '#policy-en' || hash.startsWith('#en-')) return 'en';
    const requested = new URL(window.location.href).searchParams.get('lang');
    return validLanguage(requested) ? requested : 'en';
  }

  const compactContents = window.matchMedia('(max-width: 860px)').matches;
  document.querySelectorAll('details.toc').forEach(contents => {
    contents.open = !compactContents;
  });
  selectLanguage(languageInAddress());

  choices.forEach(choice => {
    choice.addEventListener('click', event => {
      // Preserve ordinary browser behaviour for opening a link in another tab.
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      const language = choice.dataset.languageChoice;
      const previousLanguage = document.documentElement.lang;
      const previousHash = window.location.hash;
      const section = previousHash.startsWith(`#${previousLanguage}-`)
        ? previousHash.slice(previousLanguage.length + 2) : '';
      selectLanguage(language);
      const address = new URL(window.location.href);
      address.searchParams.set('lang', language);
      address.hash = section ? `${language}-${section}` : `policy-${language}`;
      window.history.pushState(null, '', address);
      const destination = document.getElementById(address.hash.slice(1));
      if (section && destination) {
        destination.scrollIntoView({ block: 'start', behavior: 'instant' });
      } else {
        window.scrollTo({top: 0, behavior: 'instant'});
      }
    });
  });

  window.addEventListener('popstate', () => selectLanguage(languageInAddress()));
  window.addEventListener('hashchange', () => selectLanguage(languageInAddress()));
})();
