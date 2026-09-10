import { I18nManager } from 'react-native';
import RNRestart from 'react-native-restart';
import { persistor } from '@/store';

/** RTL languages available in the app's language list. */
const RTL_LOCALES = ['ar', 'fa', 'he'];

/**
 * Writes the native layout-direction flags for `locale` when they differ from
 * the running direction. `forceRTL`/`swapLeftAndRightInRTL` persist natively
 * and only apply on the next launch, so this never restarts by itself — safe
 * to call on every launch without looping. Returns whether a launch is needed.
 */
export const syncRTLDirection = (locale: string): boolean => {
  const shouldBeRTL = RTL_LOCALES.includes(locale?.split('_')[0]?.toLowerCase());
  // iOS defaults doLeftAndRightSwapInRTL to false (unregistered NSUserDefaults
  // key), so physical left/right styles would not mirror even with isRTL set.
  const needsSwapFlag = shouldBeRTL && !I18nManager.doLeftAndRightSwapInRTL;
  if (I18nManager.isRTL === shouldBeRTL && !needsSwapFlag) {
    return false;
  }
  I18nManager.allowRTL(shouldBeRTL);
  I18nManager.swapLeftAndRightInRTL(true);
  I18nManager.forceRTL(shouldBeRTL);
  return true;
};

/**
 * Call right after `setLocale` was dispatched. Restarts the JS bundle once when
 * the layout direction changed. The redux-persist write is awaited first: the
 * restart tears down the bridge, which drops queued native calls, so a restart
 * issued in the same tick loses the new locale — the app comes back in the old
 * language, flips the direction back and reloads again (a reload storm).
 */
export const restartForLocaleDirection = async (locale: string) => {
  if (!syncRTLDirection(locale)) {
    return;
  }
  await persistor.flush();
  // Falls back to applying on the next manual launch if the native
  // module is missing (binary built before this dependency was added).
  RNRestart?.restart?.();
};
