import { createAsyncThunk } from '@reduxjs/toolkit';
import * as Sentry from '@sentry/react-native';

import messaging from '@react-native-firebase/messaging';
import { Platform, PermissionsAndroid } from 'react-native';
import {
  getSystemName,
  getManufacturer,
  getModel,
  getApiLevel,
  getBrand,
  getBuildNumber,
  getUniqueId,
} from 'react-native-device-info';

import { SettingsService } from './settingsService';
import type {
  NotificationSettings,
  NotificationSettingsPayload,
  PushPayload,
} from './settingsTypes';
import { handleApiError } from './settingsUtils';

const createSettingsThunk = <TResponse, TPayload>(
  type: string,
  handler: (payload: TPayload) => Promise<TResponse>,
  errorMessage?: string,
) => {
  return createAsyncThunk<TResponse, TPayload>(type, async (payload, { rejectWithValue }) => {
    try {
      return await handler(payload);
    } catch (error) {
      return rejectWithValue(handleApiError(error, errorMessage));
    }
  });
};

export const settingsActions = {
  getNotificationSettings: createSettingsThunk<NotificationSettings, void>(
    'settings/getNotificationSettings',
    () => SettingsService.getNotificationSettings(),
  ),

  updateNotificationSettings: createSettingsThunk<
    NotificationSettings,
    NotificationSettingsPayload
  >('settings/updateNotificationSettings', SettingsService.updateNotificationSettings),

  getFoxDeskVersion: createSettingsThunk<{ version: string }, { installationUrl: string }>(
    'settings/getFoxDeskVersion',
    ({ installationUrl }) => SettingsService.getFoxDeskVersion(installationUrl),
  ),

  saveDeviceDetails: createAsyncThunk<{ fcmToken: string }, void>(
    'settings/saveDeviceDetails',
    async (_, { rejectWithValue }) => {
      try {
        const permissionEnabled = await messaging().hasPermission();
        const deviceId = await getUniqueId();
        const devicePlatform = getSystemName();
        const manufacturer = await getManufacturer();
        const model = await getModel();
        const apiLevel = await getApiLevel();
        const deviceName = `${manufacturer} ${model}`;

        const isAndroidAPILevelGreater32 = apiLevel > 32 && Platform.OS === 'android';
        const brandName = await getBrand();
        const buildNumber = await getBuildNumber();

        if (!permissionEnabled || permissionEnabled === -1) {
          if (isAndroidAPILevelGreater32) {
            await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS);
          }
          await messaging().requestPermission();
        }

        const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
        // https://github.com/invertase/react-native-firebase/issues/6893#issuecomment-1427998691
        // await messaging().registerDeviceForRemoteMessages();
        await sleep(1000);
        const fcmToken = await messaging().getToken();

        const pushData: PushPayload = {
          subscription_type: 'fcm',
          subscription_attributes: {
            deviceName,
            devicePlatform,
            apiLevel: apiLevel.toString(),
            brandName,
            buildNumber,
            push_token: fcmToken,
            device_id: deviceId,
          },
        };
        await SettingsService.saveDeviceDetails(pushData);
        return { fcmToken };
      } catch (error) {
        Sentry.captureException(error);
        return rejectWithValue(
          error instanceof Error ? error.message : 'Error saving device details',
        );
      }
    },
  ),

  removeDevice: createSettingsThunk<void, { pushToken: string }>(
    'settings/removeDevice',
    ({ pushToken }) => SettingsService.removeDevice({ push_token: pushToken }),
  ),
};
