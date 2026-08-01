import { Platform } from 'react-native';
import notifee, { AndroidImportance } from '@notifee/react-native';
import type { FirebaseMessagingTypes } from '@react-native-firebase/messaging';
import { NOTIFICATION_TYPES } from '@/constants';
import { Notification } from '@/types/Notification';

export const clearAllDeliveredNotifications = async () => {
  if (Platform.OS === 'ios') {
    await notifee.cancelAllNotifications();
  }
};

export const updateBadgeCount = async ({ count = 0 }) => {
  if (Platform.OS === 'ios' && count >= 0) {
    await notifee.setBadgeCount(count);
  }
};

export const displayForegroundNotification = async (
  message: FirebaseMessagingTypes.RemoteMessage,
) => {
  if (Platform.OS !== 'android' || !message.notification) {
    return;
  }

  const channelId = await notifee.createChannel({
    id: 'messages',
    name: 'FoxDesk Ai messages',
    importance: AndroidImportance.HIGH,
  });

  await notifee.displayNotification({
    title: message.notification.title,
    body: message.notification.body,
    data: message.data,
    android: {
      channelId,
      pressAction: {
        id: 'default',
      },
    },
  });
};

export const findConversationLinkFromPush = ({
  notification,
  installationUrl,
}: {
  notification: Notification;
  installationUrl: string;
}) => {
  const navigationParams = findConversationNavigationParamsFromPush({ notification });

  if (navigationParams) {
    const { conversationId, primaryActorId, primaryActorType } = navigationParams;
    return `${installationUrl}/app/accounts/1/conversations/${conversationId}/${primaryActorId}/${primaryActorType}`;
  }
  return;
};

export const findConversationNavigationParamsFromPush = ({
  notification,
}: {
  notification: Notification;
}) => {
  const { notificationType, primaryActor, primaryActorId, primaryActorType } = notification;

  if (NOTIFICATION_TYPES.includes(notificationType)) {
    let conversationId = null;
    if (primaryActorType === 'Conversation') {
      conversationId = primaryActor.id;
    } else if (primaryActorType === 'Message') {
      conversationId = primaryActor.conversationId;
    }
    if (conversationId) {
      return { conversationId, primaryActorId, primaryActorType };
    }
  }
  return;
};

interface FCMMessage {
  data?: {
    payload?: string;
    notification?: string;
  };
}

export const findNotificationFromFCM = ({ message }: { message: FCMMessage }) => {
  let notification = null;
  // FCM HTTP v1
  const { data } = message;
  if (data?.payload) {
    const parsedPayload = JSON.parse(data.payload);
    notification = parsedPayload.data.notification;
  }
  // FCM legacy. It will be deprecated soon
  else if (data?.notification) {
    notification = JSON.parse(data.notification);
  }
  return notification;
};
