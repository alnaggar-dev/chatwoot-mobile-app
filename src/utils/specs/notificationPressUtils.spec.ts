import AsyncStorage from '@react-native-async-storage/async-storage';

import {
  clearPendingNotificationData,
  findConversationNavigationParamsFromData,
  getPendingNotificationData,
  storePendingNotificationData,
} from '../notificationPressUtils';

jest.mock('@react-native-async-storage/async-storage', () => ({
  __esModule: true,
  default: {
    getItem: jest.fn(),
    removeItem: jest.fn(),
    setItem: jest.fn(),
  },
}));

describe('notificationPressUtils', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('extracts conversation navigation params from Notifee data', () => {
    const data = {
      payload: JSON.stringify({
        data: {
          notification: {
            notification_type: 'conversation_assignment',
            primary_actor_id: 14902,
            primary_actor_type: 'Conversation',
            primary_actor: { id: 14428 },
          },
        },
      }),
    };

    expect(findConversationNavigationParamsFromData(data)).toEqual({
      conversationId: 14428,
      primaryActorId: 14902,
      primaryActorType: 'Conversation',
    });
  });

  it('stores and reads pending notification data', async () => {
    const data = { notification: '{"id":1}' };
    jest.mocked(AsyncStorage.getItem).mockResolvedValue(JSON.stringify(data));

    await storePendingNotificationData(data);
    await expect(getPendingNotificationData()).resolves.toEqual(data);

    expect(AsyncStorage.setItem).toHaveBeenCalledWith(
      '@foxdesk/pending-notification-data',
      JSON.stringify(data),
    );

    await clearPendingNotificationData();
    expect(AsyncStorage.removeItem).toHaveBeenCalledWith('@foxdesk/pending-notification-data');
  });
});
