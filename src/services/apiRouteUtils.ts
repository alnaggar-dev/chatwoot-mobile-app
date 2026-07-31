const nonAccountRoutes = [
  'profile',
  'profile/availability',
  'notification_subscriptions',
  'profile/set_active_account',
];

const fullyScopedRoutePrefixes = ['api/v1/accounts/', 'enterprise/api/v1/accounts/'];

export const getScopedApiUrl = (
  url: string | undefined,
  accountId?: number,
): string | undefined => {
  if (!url || fullyScopedRoutePrefixes.some(prefix => url.startsWith(prefix))) return url;
  if (nonAccountRoutes.includes(url)) return `api/v1/${url}`;
  if (accountId) return `api/v1/accounts/${accountId}/${url}`;
  return url;
};
