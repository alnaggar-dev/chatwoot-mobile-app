import AsyncStorage from '@react-native-async-storage/async-storage';
import type { Notification as NotifeeNotification } from '@notifee/react-native';

import { transformNotification } from '@/utils/camelCaseKeys';
import {
  findConversationNavigationParamsFromPush,
  findNotificationFromFCM,
} from '@/utils/pushUtils';

export type NotificationData = NonNullable<NotifeeNotification['data']>;

const PENDING_NOTIFICATION_DATA_KEY = '@foxdesk/pending-notification-data';

export const findConversationNavigationParamsFromData = (data?: NotificationData) => {
  if (!data) {
    return;
  }

  const payload = typeof data.payload === 'string' ? data.payload : undefined;
  const notification = typeof data.notification === 'string' ? data.notification : undefined;

  try {
    const parsedNotification = findNotificationFromFCM({
      message: { data: { payload, notification } },
    });

    return findConversationNavigationParamsFromPush({
      notification: transformNotification(parsedNotification),
    });
  } catch {
    return;
  }
};

export const storePendingNotificationData = async (data?: NotificationData) => {
  if (data) {
    await AsyncStorage.setItem(PENDING_NOTIFICATION_DATA_KEY, JSON.stringify(data));
  }
};

export const getPendingNotificationData = async (): Promise<NotificationData | undefined> => {
  const data = await AsyncStorage.getItem(PENDING_NOTIFICATION_DATA_KEY);

  if (!data) {
    return;
  }

  try {
    return JSON.parse(data) as NotificationData;
  } catch {
    await AsyncStorage.removeItem(PENDING_NOTIFICATION_DATA_KEY);
    return;
  }
};

export const clearPendingNotificationData = () =>
  AsyncStorage.removeItem(PENDING_NOTIFICATION_DATA_KEY);
