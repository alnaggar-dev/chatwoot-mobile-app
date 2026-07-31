import { Platform } from 'react-native';
import notifee, { AndroidImportance } from '@notifee/react-native';
import { transformNotification } from '../camelCaseKeys';
import {
  displayForegroundNotification,
  findConversationLinkFromPush,
  findNotificationFromFCM,
} from '../pushUtils';

jest.mock('@notifee/react-native', () => ({
  __esModule: true,
  AndroidImportance: { HIGH: 4 },
  default: {
    cancelAllNotifications: jest.fn(),
    createChannel: jest.fn(async channel => channel.id),
    displayNotification: jest.fn(),
    setBadgeCount: jest.fn(),
  },
}));

describe('displayForegroundNotification', () => {
  it('displays Android messages on a high-priority channel', async () => {
    const platform = jest.replaceProperty(Platform, 'OS', 'android');

    await displayForegroundNotification({
      messageId: 'message-1',
      data: { payload: '{"notification":"message"}' },
      notification: { title: 'New message', body: 'A customer replied' },
      fcmOptions: {},
    });

    expect(notifee.createChannel).toHaveBeenCalledWith({
      id: 'messages',
      name: 'FoxDesk Ai messages',
      importance: AndroidImportance.HIGH,
    });
    expect(notifee.displayNotification).toHaveBeenCalledWith({
      title: 'New message',
      body: 'A customer replied',
      data: { payload: '{"notification":"message"}' },
      android: {
        channelId: 'messages',
        pressAction: { id: 'default' },
      },
    });

    platform.restore();
  });
});

describe('findNotificationFromFCM', () => {
  it('should return notification from FCM HTTP v1 message', () => {
    const message = {
      data: {
        payload: '{"data": {"notification": {"id": 123, "title": "Test Notification"}}}',
      },
    };
    const result = findNotificationFromFCM({ message });
    expect(result).toEqual({ id: 123, title: 'Test Notification' });
  });

  it('should return notification from FCM legacy message', () => {
    const message = {
      data: {
        notification: '{"id": 456, "title": "Legacy Notification"}',
      },
    };
    const result = findNotificationFromFCM({ message });
    expect(result).toEqual({ id: 456, title: 'Legacy Notification' });
  });
});

describe('findConversationLinkFromPush', () => {
  it('should return conversation link if notification_type is conversation_creation', () => {
    const notification = {
      id: 8687,
      notificationType: 'conversation_creation',
      primaryActorId: 14902,
      primaryActorType: 'Conversation',
      primaryActor: { id: 14428 },
    };
    const installationUrl = 'https://app.foxdeskai.com';
    const transformedNotification = transformNotification(notification);
    const result = findConversationLinkFromPush({
      notification: transformedNotification,
      installationUrl,
    });
    expect(result).toBe(
      'https://app.foxdeskai.com/app/accounts/1/conversations/14428/14902/Conversation',
    );
  });

  it('should return conversation link if notification_type is assigned_conversation_new_message', () => {
    const notification = {
      id: 8694,
      notificationType: 'assigned_conversation_new_message',
      primaryActorId: 58731,
      primaryActorType: 'Message',
      primaryActor: { conversationId: 14429, id: 58731 },
    };
    const installationUrl = 'https://app.foxdeskai.com';
    const transformedNotification = transformNotification(notification);
    const result = findConversationLinkFromPush({
      notification: transformedNotification,
      installationUrl,
    });
    expect(result).toBe(
      'https://app.foxdeskai.com/app/accounts/1/conversations/14429/58731/Message',
    );
  });

  it('should return conversation link if notification_type is conversation_mention', () => {
    const notification = {
      id: 8690,
      notificationType: 'conversation_mention',
      primaryActorId: 58725,
      primaryActorType: 'Message',
      primaryActor: { conversationId: 14428, id: 58725 },
    };
    const installationUrl = 'https://app.foxdeskai.com';
    const transformedNotification = transformNotification(notification);
    const result = findConversationLinkFromPush({
      notification: transformedNotification,
      installationUrl,
    });
    expect(result).toBe(
      'https://app.foxdeskai.com/app/accounts/1/conversations/14428/58725/Message',
    );
  });

  it('should return conversation link if notification_type is participating_conversation_new_message', () => {
    const notification = {
      id: 8678,
      notificationType: 'participating_conversation_new_message',
      primaryActorId: 58712,
      primaryActorType: 'Message',
      primaryActor: { conversationId: 14427, id: 58712 },
    };
    const installationUrl = 'https://app.foxdeskai.com';
    const transformedNotification = transformNotification(notification);
    const result = findConversationLinkFromPush({
      notification: transformedNotification,
      installationUrl,
    });
    expect(result).toBe(
      'https://app.foxdeskai.com/app/accounts/1/conversations/14427/58712/Message',
    );
  });

  it('should return nothing if notification_type is not valid', () => {
    const notification = {
      id: 8678,
      notificationType: 'participating_conversation_message',
      primaryActorId: 58712,
      primaryActorType: 'Message',
      primaryActor: { conversationId: 14427, id: 58712 },
    };
    const installationUrl = 'https://app.foxdeskai.com';
    const transformedNotification = transformNotification(notification);
    const result = findConversationLinkFromPush({
      notification: transformedNotification,
      installationUrl,
    });
    expect(result).toBe(undefined);
  });
});
