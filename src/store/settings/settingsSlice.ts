import { createSlice } from '@reduxjs/toolkit';
import { settingsActions } from './settingsActions';
import { NotificationSettings } from './settingsTypes';
import { Theme } from '@/types/common/Theme';

interface SettingsState {
  baseUrl: string;
  installationUrl: string;
  uiFlags: {
    isUpdating: boolean;
    isLocaleSet: boolean;
  };
  notificationSettings: NotificationSettings;
  localeValue: string;
  webSocketUrl: string;
  theme: Theme;
  version: string;
  pushToken: string;
}

export const INSTALLATION_URL_DEFAULTS: Pick<
  SettingsState,
  'baseUrl' | 'installationUrl' | 'webSocketUrl'
> = {
  baseUrl: 'app.foxdeskai.com',
  installationUrl: 'https://app.foxdeskai.com/',
  webSocketUrl: 'wss://app.foxdeskai.com/cable',
};
const initialState: SettingsState = {
  ...INSTALLATION_URL_DEFAULTS,
  uiFlags: {
    isUpdating: false,
    isLocaleSet: false,
  },
  localeValue: 'en',
  notificationSettings: {
    account_id: 0,
    all_email_flags: [],
    all_push_flags: [],
    id: 0,
    selected_email_flags: [],
    selected_push_flags: [],
    user_id: 0,
  },
  theme: 'system',
  version: '',
  pushToken: '',
};
export const settingsSlice = createSlice({
  name: 'settings',
  initialState,
  reducers: {
    resetSettings: state => {
      state.uiFlags.isUpdating = false;
    },
    setLocale: (state, action) => {
      state.localeValue = action.payload;
      state.uiFlags.isLocaleSet = true;
    },
  },
  extraReducers: builder => {
    builder
      .addCase(settingsActions.getNotificationSettings.fulfilled, (state, action) => {
        state.notificationSettings = action.payload;
      })
      .addCase(settingsActions.updateNotificationSettings.pending, state => {
        state.uiFlags.isUpdating = true;
      })
      .addCase(settingsActions.updateNotificationSettings.fulfilled, (state, action) => {
        state.uiFlags.isUpdating = false;
        state.notificationSettings = action.payload;
      })
      .addCase(settingsActions.updateNotificationSettings.rejected, state => {
        state.uiFlags.isUpdating = false;
      })
      .addCase(settingsActions.getFoxDeskVersion.fulfilled, (state, action) => {
        const { version } = action.payload;
        state.version = version;
      })
      .addCase(settingsActions.saveDeviceDetails.fulfilled, (state, action) => {
        if (action?.payload?.fcmToken) {
          state.pushToken = action.payload.fcmToken;
        }
      })
      .addCase(settingsActions.saveDeviceDetails.rejected, (state, action) => {
        state.pushToken = '';
      });
  },
});
export const { resetSettings, setLocale } = settingsSlice.actions;
export default settingsSlice.reducer;
