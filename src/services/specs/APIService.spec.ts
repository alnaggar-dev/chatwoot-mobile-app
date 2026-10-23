import { configureStore } from '@reduxjs/toolkit';
import type { InternalAxiosRequestConfig } from 'axios';
import { Platform } from 'react-native';

import type { apiService as ApiService } from '@/services/APIService';
import { setStore } from '@/store/storeAccessor';

jest.mock('expo-constants', () => ({
  __esModule: true,
  default: { expoConfig: { version: '4.2.0' } },
}));

jest.mock('expo-device', () => ({
  osVersion: '14',
  modelName: 'Pixel 8',
}));

const authState = { headers: null, user: { account_id: 7 } };
const settingsState = { installationUrl: 'https://app.foxdesk.test/' };

const sendRequest = async (service: typeof ApiService) => {
  let sent: InternalAxiosRequestConfig | undefined;
  await service.get('conversations', {
    adapter: async config => {
      sent = config;
      return { data: {}, status: 200, statusText: 'OK', headers: {}, config };
    },
  });
  return (sent?.headers.toJSON() ?? {}) as Record<string, string>;
};

describe('apiService client headers', () => {
  let headers: Record<string, string>;

  beforeAll(async () => {
    setStore(
      configureStore({
        reducer: { auth: () => authState, settings: () => settingsState },
      }),
    );
    jest.replaceProperty(Platform, 'OS', 'android');
    // The headers are built once when the module loads, after the platform stub.
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { apiService } = require('@/services/APIService');
    headers = await sendRequest(apiService);
  });

  it('sends the device details as X-Foxdeskai-* headers', () => {
    expect(headers).toMatchObject({
      'X-Foxdeskai-Client-Name': 'FoxDesk Ai Mobile',
      'X-Foxdeskai-Client-Version': '4.2.0',
      'X-Foxdeskai-Platform': 'android',
      'X-Foxdeskai-Platform-Version': '14',
      'X-Foxdeskai-Device-Model': 'Pixel 8',
    });
  });

  it('sends no X- client header besides the five X-Foxdeskai-* ones', () => {
    const clientHeaderNames = Object.keys(headers).filter(name => /^x-/i.test(name));
    expect(clientHeaderNames.sort()).toEqual([
      'X-Foxdeskai-Client-Name',
      'X-Foxdeskai-Client-Version',
      'X-Foxdeskai-Device-Model',
      'X-Foxdeskai-Platform',
      'X-Foxdeskai-Platform-Version',
    ]);
  });

  it('keeps the FoxDesk Ai Mobile User-Agent', () => {
    expect(headers['User-Agent']).toBe('FoxDesk Ai Mobile/4.2.0 (android 14; Pixel 8)');
  });
});
