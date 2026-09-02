import { createSelector } from '@reduxjs/toolkit';
import { RootState } from '@/store';
import { selectUserId } from '@/store/auth/authSelectors';

export const selectSettings = (state: RootState) => state.settings;

export const selectInstallationUrl = createSelector(
  selectSettings,
  settings => settings.installationUrl,
);

export const selectLocale = createSelector(selectSettings, settings =>
  settings.localeValue === 'zh' ? 'zh_CN' : settings.localeValue,
);

export const selectIsLocaleSet = createSelector(
  selectSettings,
  settings => settings.uiFlags.isLocaleSet,
);

export const selectNotificationSettings = createSelector(
  selectSettings,
  settings => settings.notificationSettings,
);

export const selectWebSocketUrl = createSelector(selectSettings, settings => settings.webSocketUrl);

export const selectTheme = createSelector(selectSettings, settings => settings.theme);

export const selectIsFoxDeskCloud = createSelector(selectSettings, settings =>
  settings.installationUrl.includes('app.foxdeskai.com'),
);

export const selectFoxDeskVersion = createSelector(selectSettings, settings => settings.version);

export const selectPushToken = createSelector(selectSettings, settings => settings.pushToken);

export const selectCaptainConsent = createSelector(
  [selectSettings, selectUserId],
  (settings, userId) => userId !== undefined && settings.captainConsentByUser?.[userId] === true,
);
