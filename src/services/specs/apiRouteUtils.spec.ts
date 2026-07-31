import { getScopedApiUrl } from '@/services/apiRouteUtils';

describe('getScopedApiUrl', () => {
  it('scopes regular account requests', () => {
    expect(getScopedApiUrl('conversations', 42)).toBe('api/v1/accounts/42/conversations');
  });

  it('scopes profile requests outside the account', () => {
    expect(getScopedApiUrl('profile', 42)).toBe('api/v1/profile');
  });

  it.each(['api/v1/accounts/42', 'enterprise/api/v1/accounts/42/toggle_deletion'])(
    'preserves the fully scoped route %s',
    url => {
      expect(getScopedApiUrl(url, 42)).toBe(url);
    },
  );
});
