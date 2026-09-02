import { I18nManager } from 'react-native';
import RNRestart from 'react-native-restart';
import { syncRTLDirection } from '../rtlUtils';

jest.mock('react-native-restart', () => ({
  __esModule: true,
  default: { restart: jest.fn() },
}));

const mockNativeDirection = (isRTL: boolean, doLeftAndRightSwapInRTL: boolean) => {
  jest.replaceProperty(I18nManager, 'isRTL', isRTL);
  jest.replaceProperty(I18nManager, 'doLeftAndRightSwapInRTL', doLeftAndRightSwapInRTL);
};

describe('syncRTLDirection', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(I18nManager, 'allowRTL').mockImplementation(() => {});
    jest.spyOn(I18nManager, 'forceRTL').mockImplementation(() => {});
    jest.spyOn(I18nManager, 'swapLeftAndRightInRTL').mockImplementation(() => {});
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('forces RTL and restarts when an RTL language is picked on an LTR launch', () => {
    mockNativeDirection(false, true);

    syncRTLDirection('ar');

    expect(I18nManager.allowRTL).toHaveBeenCalledWith(true);
    expect(I18nManager.swapLeftAndRightInRTL).toHaveBeenCalledWith(true);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(true);
    expect(RNRestart.restart).toHaveBeenCalledTimes(1);
  });

  it('forces LTR and restarts when an LTR language is picked on an RTL launch', () => {
    mockNativeDirection(true, true);

    syncRTLDirection('en');

    expect(I18nManager.allowRTL).toHaveBeenCalledWith(false);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(false);
    expect(RNRestart.restart).toHaveBeenCalledTimes(1);
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

    syncRTLDirection('ar');

    expect(I18nManager.forceRTL).not.toHaveBeenCalled();
    expect(I18nManager.swapLeftAndRightInRTL).not.toHaveBeenCalled();
    expect(RNRestart.restart).not.toHaveBeenCalled();
  });

  it('sets the swap flag on an RTL launch that never enabled it (iOS default)', () => {
    mockNativeDirection(true, false);

    syncRTLDirection('ar');

    expect(I18nManager.swapLeftAndRightInRTL).toHaveBeenCalledWith(true);
    expect(I18nManager.forceRTL).toHaveBeenCalledWith(true);
    expect(RNRestart.restart).toHaveBeenCalledTimes(1);
  });
});
