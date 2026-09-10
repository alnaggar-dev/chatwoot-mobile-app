import { I18nManager } from 'react-native';
import RNRestart from 'react-native-restart';
import { persistor } from '@/store';
import { restartForLocaleDirection, syncRTLDirection } from '../rtlUtils';

jest.mock('react-native-restart', () => ({
  __esModule: true,
  default: { restart: jest.fn() },
}));

jest.mock('@/store', () => ({
  persistor: { flush: jest.fn() },
}));

const mockNativeDirection = (isRTL: boolean, doLeftAndRightSwapInRTL: boolean) => {
  jest.replaceProperty(I18nManager, 'isRTL', isRTL);
  jest.replaceProperty(I18nManager, 'doLeftAndRightSwapInRTL', doLeftAndRightSwapInRTL);
};

beforeEach(() => {
  jest.clearAllMocks();
  jest.spyOn(I18nManager, 'allowRTL').mockImplementation(() => {});
  jest.spyOn(I18nManager, 'forceRTL').mockImplementation(() => {});
  jest.spyOn(I18nManager, 'swapLeftAndRightInRTL').mockImplementation(() => {});
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe('syncRTLDirection', () => {
  it('forces RTL when an RTL language is picked on an LTR launch', () => {
    mockNativeDirection(false, true);

    expect(syncRTLDirection('ar')).toBe(true);

    expect(I18nManager.allowRTL).toHaveBeenCalledWith(true);
    expect(I18nManager.swapLeftAndRightInRTL).toHaveBeenCalledWith(true);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(true);
  });

  it('forces LTR when an LTR language is picked on an RTL launch', () => {
    mockNativeDirection(true, true);

    expect(syncRTLDirection('en')).toBe(true);

    expect(I18nManager.allowRTL).toHaveBeenCalledWith(false);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(false);
  });

  it('never restarts by itself, so it is safe on every launch', () => {
    mockNativeDirection(false, true);

    syncRTLDirection('ar');

    expect(RNRestart.restart).not.toHaveBeenCalled();
  });

  it.each(['fa', 'he'])('treats %s as right-to-left', locale => {
    mockNativeDirection(false, true);

    syncRTLDirection(locale);

    expect(I18nManager.forceRTL).toHaveBeenCalledWith(true);
  });

  it.each(['en', 'pt_BR', 'zh_CN'])('treats %s as left-to-right', locale => {
    mockNativeDirection(true, true);

    syncRTLDirection(locale);

    expect(I18nManager.forceRTL).toHaveBeenCalledWith(false);
  });

  it('does nothing when the native direction already matches the language', () => {
    mockNativeDirection(true, true);

    expect(syncRTLDirection('ar')).toBe(false);

    expect(I18nManager.forceRTL).not.toHaveBeenCalled();
    expect(I18nManager.swapLeftAndRightInRTL).not.toHaveBeenCalled();
  });

  it('sets the swap flag on an RTL launch that never enabled it (iOS default)', () => {
    mockNativeDirection(true, false);

    expect(syncRTLDirection('ar')).toBe(true);

    expect(I18nManager.swapLeftAndRightInRTL).toHaveBeenCalledWith(true);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(true);
  });
});

describe('restartForLocaleDirection', () => {
  it('persists the locale before restarting when the direction changes', async () => {
    mockNativeDirection(false, true);
    let flushed = false;
    (persistor.flush as jest.Mock).mockImplementation(async () => {
      expect(RNRestart.restart).not.toHaveBeenCalled();
      flushed = true;
    });

    await restartForLocaleDirection('ar');

    expect(flushed).toBe(true);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(true);
    expect(RNRestart.restart).toHaveBeenCalledTimes(1);
  });

  it('neither flushes nor restarts when the direction is unchanged', async () => {
    mockNativeDirection(false, true);

    await restartForLocaleDirection('de');

    expect(persistor.flush).not.toHaveBeenCalled();
    expect(RNRestart.restart).not.toHaveBeenCalled();
  });
});
