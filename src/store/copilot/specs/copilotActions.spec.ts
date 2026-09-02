import { RootState } from '@/store';
import { COPILOT_CONSENT_REQUIRED } from '@/constants/copilot';
import { executeCopilotAction, sendCopilotFollowUp } from '../copilotActions';
import { CopilotService } from '../copilotService';

jest.mock('../copilotService', () => ({
  CopilotService: {
    rewrite: jest.fn(),
    summarize: jest.fn(),
    replySuggestion: jest.fn(),
    followUp: jest.fn(),
  },
}));

const USER_ID = 1;

const buildState = (allowed: boolean) =>
  ({
    settings: { captainConsentByUser: { [USER_ID]: allowed } },
    auth: { user: { id: USER_ID } },
  }) as unknown as RootState;

const dispatch = jest.fn();

describe('Copilot Actions consent gate', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('executeCopilotAction', () => {
    const payload = { actionKey: 'summarize' as const, content: '', conversationId: 1 };

    it('rejects with COPILOT_CONSENT_REQUIRED and skips the network when consent is missing', async () => {
      const result = await executeCopilotAction(payload)(
        dispatch,
        () => buildState(false),
        undefined,
      );

      expect(result.type).toBe(executeCopilotAction.rejected.type);
      expect(result.payload).toEqual({ name: COPILOT_CONSENT_REQUIRED });
      expect(CopilotService.summarize).not.toHaveBeenCalled();
    });

    it('calls the service when consent is granted', async () => {
      (CopilotService.summarize as jest.Mock).mockResolvedValueOnce({ message: 'ok' });

      const result = await executeCopilotAction(payload)(
        dispatch,
        () => buildState(true),
        undefined,
      );

      expect(result.type).toBe(executeCopilotAction.fulfilled.type);
      expect(CopilotService.summarize).toHaveBeenCalledWith(
        { conversationId: 1 },
        expect.any(AbortSignal),
      );
    });
  });

  describe('sendCopilotFollowUp', () => {
    const payload = { followUpContext: {}, message: 'hi', conversationId: 1 };

    it('rejects with COPILOT_CONSENT_REQUIRED and skips the network when consent is missing', async () => {
      const result = await sendCopilotFollowUp(payload)(
        dispatch,
        () => buildState(false),
        undefined,
      );

      expect(result.type).toBe(sendCopilotFollowUp.rejected.type);
      expect(result.payload).toEqual({ name: COPILOT_CONSENT_REQUIRED });
      expect(CopilotService.followUp).not.toHaveBeenCalled();
    });

    it('calls the service when consent is granted', async () => {
      (CopilotService.followUp as jest.Mock).mockResolvedValueOnce({ message: 'ok' });

      const result = await sendCopilotFollowUp(payload)(
        dispatch,
        () => buildState(true),
        undefined,
      );

      expect(result.type).toBe(sendCopilotFollowUp.fulfilled.type);
      expect(CopilotService.followUp).toHaveBeenCalledWith(payload, expect.any(AbortSignal));
    });
  });
});
