const currentSite = 'https://thedrvn.netlify.app';
// Migrate the former Netlify URL even when SITE_URL still contains it.
export function siteUrl(configured = '') {
  const value = configured.trim().replace(/\/+$/, '');
  return !value || value === 'https://shainetesting.netlify.app' ? currentSite : value;
}
