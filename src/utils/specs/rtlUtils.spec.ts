import type * as ReactNative from 'react-native';
import type * as RtlUtils from '../rtlUtils';

jest.mock('react-native-restart', () => ({
  __esModule: true,
  default: { restart: jest.fn() },
}));

jest.mock('@/store', () => ({
  persistor: { flush: jest.fn() },
}));

jest.mock('@react-native-async-storage/async-storage', () => ({
  __esModule: true,
  default: { getItem: jest.fn(async () => null), setItem: jest.fn(), removeItem: jest.fn() },
}));

/**
 * Loads rtlUtils the way a JS VM that started with the given native direction
 * would. The module captures I18nManager.isRTL once at import, so a static
 * import cannot model a launch — each test resets the registry and re-requires
 * (babel keeps `import()` native here, which Jest cannot run).
 */
const launchWith = (isRTL: boolean) => {
  jest.resetModules();
  /* eslint-disable @typescript-eslint/no-require-imports */
  const { I18nManager }: typeof ReactNative = require('react-native');
  jest.replaceProperty(I18nManager, 'isRTL', isRTL);
  jest.spyOn(I18nManager, 'allowRTL').mockImplementation(() => {});
  jest.spyOn(I18nManager, 'forceRTL').mockImplementation(() => {});
  jest.spyOn(I18nManager, 'swapLeftAndRightInRTL').mockImplementation(() => {});
  const utils: typeof RtlUtils = require('../rtlUtils');
  const restart: jest.Mock = require('react-native-restart').default.restart;
  const flush: jest.Mock = require('@/store').persistor.flush;
  const storage: Record<'getItem' | 'setItem' | 'removeItem', jest.Mock> =
    require('@react-native-async-storage/async-storage').default;
  /* eslint-enable @typescript-eslint/no-require-imports */
  return { ...utils, I18nManager, restart, flush, storage };
};

afterEach(() => {
  jest.restoreAllMocks();
});

describe('syncRTLDirection', () => {
  it('forces RTL when an RTL language is picked on an LTR launch', () => {
    const { syncRTLDirection, I18nManager } = launchWith(false);

    expect(syncRTLDirection('ar')).toBe(true);

    expect(I18nManager.allowRTL).toHaveBeenCalledWith(true);
    expect(I18nManager.swapLeftAndRightInRTL).toHaveBeenCalledWith(true);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(true);
  });

  it('forces LTR when an LTR language is picked on an RTL launch', () => {
    const { syncRTLDirection, I18nManager } = launchWith(true);

    expect(syncRTLDirection('en')).toBe(true);

    expect(I18nManager.allowRTL).toHaveBeenCalledWith(false);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(false);
  });

  it('never restarts by itself', () => {
    const { syncRTLDirection, restart } = launchWith(false);

    syncRTLDirection('ar');

    expect(restart).not.toHaveBeenCalled();
  });

  it.each(['fa', 'he'])('treats %s as right-to-left', locale => {
    const { syncRTLDirection, I18nManager } = launchWith(false);

    syncRTLDirection(locale);

    expect(I18nManager.forceRTL).toHaveBeenCalledWith(true);
  });

  it.each(['en', 'pt_BR', 'zh_CN'])('treats %s as left-to-right', locale => {
    const { syncRTLDirection, I18nManager } = launchWith(true);

    syncRTLDirection(locale);

    expect(I18nManager.forceRTL).toHaveBeenCalledWith(false);
  });

  it('does nothing when the native direction already matches the language', () => {
    const { syncRTLDirection, I18nManager } = launchWith(true);

    expect(syncRTLDirection('ar')).toBe(false);

    expect(I18nManager.forceRTL).not.toHaveBeenCalled();
    expect(I18nManager.swapLeftAndRightInRTL).not.toHaveBeenCalled();
  });

  it('compares against the direction it already wrote, not the launch constant', () => {
    // RTL launch whose saved language is LTR: the launch sync flips the flags,
    // then the user picks Arabic in the same session.
    const { syncRTLDirection, I18nManager } = launchWith(true);
    expect(syncRTLDirection('en')).toBe(true);
    (I18nManager.forceRTL as jest.Mock).mockClear();

    expect(syncRTLDirection('fr')).toBe(false);
    expect(I18nManager.forceRTL).not.toHaveBeenCalled();

    expect(syncRTLDirection('ar')).toBe(true);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(true);
  });
});

describe('restartForLocaleDirection', () => {
  it('persists the locale before restarting when the direction changes', async () => {
    const { restartForLocaleDirection, I18nManager, restart, flush } = launchWith(false);
    let flushed = false;
    flush.mockImplementation(async () => {
      expect(restart).not.toHaveBeenCalled();
      flushed = true;
    });

    await restartForLocaleDirection('ar');

    expect(flushed).toBe(true);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(true);
    expect(restart).toHaveBeenCalledTimes(1);
  });

  it('neither flushes nor restarts when the direction is unchanged', async () => {
    const { restartForLocaleDirection, restart, flush } = launchWith(false);

    await restartForLocaleDirection('de');

    expect(flush).not.toHaveBeenCalled();
    expect(restart).not.toHaveBeenCalled();
  });
});

describe('repairLocaleDirectionAtLaunch', () => {
  it('does nothing on a launch whose direction matches the saved language', async () => {
    const { repairLocaleDirectionAtLaunch, I18nManager, restart, storage } = launchWith(false);

    await repairLocaleDirectionAtLaunch('en');

    expect(I18nManager.forceRTL).not.toHaveBeenCalled();
    expect(storage.setItem).not.toHaveBeenCalled();
    expect(restart).not.toHaveBeenCalled();
  });

  it('marks the reload in storage before restarting when the direction disagrees', async () => {
    const { repairLocaleDirectionAtLaunch, I18nManager, restart, flush, storage } =
      launchWith(true);
    const order: string[] = [];
    storage.setItem.mockImplementation(async () => order.push('mark'));
    flush.mockImplementation(async () => order.push('flush'));
    restart.mockImplementation(() => order.push('restart'));

    await repairLocaleDirectionAtLaunch('en');

    expect(I18nManager.forceRTL).toHaveBeenCalledWith(false);
    expect(storage.setItem).toHaveBeenCalledWith(expect.any(String), 'en');
    expect(order).toEqual(['mark', 'flush', 'restart']);
  });

  it('never reloads twice in a row: a launch that finds the mark applies the flags and clears it', async () => {
    // The previous launch reloaded but the new bridge still saw the old flags.
    const { repairLocaleDirectionAtLaunch, I18nManager, restart, flush, storage } =
      launchWith(true);
    storage.getItem.mockResolvedValue('en');

    await repairLocaleDirectionAtLaunch('en');

    expect(storage.removeItem).toHaveBeenCalledTimes(1);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(false);
    expect(flush).not.toHaveBeenCalled();
    expect(restart).not.toHaveBeenCalled();
  });

  it('clears a stale mark on a healthy launch', async () => {
    const { repairLocaleDirectionAtLaunch, restart, storage } = launchWith(false);
    storage.getItem.mockResolvedValue('en');

    await repairLocaleDirectionAtLaunch('en');

    expect(storage.removeItem).toHaveBeenCalledTimes(1);
    expect(restart).not.toHaveBeenCalled();
  });
});
