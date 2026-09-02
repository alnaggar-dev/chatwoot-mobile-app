import { RootState } from '@/store';
import settingsReducer, { SettingsState, setCaptainConsent } from '../settingsSlice';
import { selectCaptainConsent } from '../settingsSelectors';

const buildState = (
  captainConsentByUser: Record<number, boolean> | undefined,
  userId: number | undefined,
) =>
  ({
    settings: { captainConsentByUser },
    auth: { user: userId === undefined ? null : { id: userId } },
  }) as unknown as RootState;

describe('Captain consent', () => {
  describe('setCaptainConsent reducer', () => {
    it('sets consent per user without clobbering other users', () => {
      const state = { captainConsentByUser: { 1: true } } as unknown as SettingsState;

      const next = settingsReducer(state, setCaptainConsent({ userId: 2, allowed: true }));

      expect(next.captainConsentByUser).toEqual({ 1: true, 2: true });
    });

    it('clears consent for a user', () => {
      const state = { captainConsentByUser: { 1: true, 2: true } } as unknown as SettingsState;

      const next = settingsReducer(state, setCaptainConsent({ userId: 1, allowed: false }));

      expect(next.captainConsentByUser).toEqual({ 1: false, 2: true });
    });

    it('tolerates rehydrated state without captainConsentByUser', () => {
      const state = { localeValue: 'en' } as SettingsState;

      const next = settingsReducer(state, setCaptainConsent({ userId: 7, allowed: true }));

      expect(next.captainConsentByUser).toEqual({ 7: true });
    });
  });

  describe('selectCaptainConsent', () => {
    it('returns false when the consent map is missing', () => {
      expect(selectCaptainConsent(buildState(undefined, 1))).toBe(false);
    });

    it('returns false when the user has no entry', () => {
      expect(selectCaptainConsent(buildState({ 2: true }, 1))).toBe(false);
    });

    it('returns false when the user is not logged in', () => {
      expect(selectCaptainConsent(buildState({ 1: true }, undefined))).toBe(false);
    });

    it('returns false when consent was withdrawn', () => {
      expect(selectCaptainConsent(buildState({ 1: false }, 1))).toBe(false);
    });

    it('returns true only when the current user allowed it', () => {
      expect(selectCaptainConsent(buildState({ 1: true, 2: false }, 1))).toBe(true);
    });
  });
});
