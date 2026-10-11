import test from 'node:test';
import assert from 'node:assert/strict';
import {siteUrl} from '../supabase/functions/drvn-api/site.mjs';
test('domain rename migrates default and stale SITE_URL used by CORS and email links', () => {
  for (const value of ['', 'https://shainetesting.netlify.app', ' https://shainetesting.netlify.app/ ', 'https://thedrvn.netlify.app/']) {
    assert.equal(siteUrl(value), 'https://thedrvn.netlify.app');
    assert.equal(`${siteUrl(value)}/status.html#token`, 'https://thedrvn.netlify.app/status.html#token');
  }
  assert.equal(siteUrl('https://example.com/'), 'https://example.com');
});
