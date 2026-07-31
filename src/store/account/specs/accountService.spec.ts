import { apiService } from '@/services/APIService';
import { AccountService } from '@/store/account/accountService';

jest.mock('@/services/APIService', () => ({
  apiService: {
    get: jest.fn(),
    post: jest.fn(),
  },
}));

describe('AccountService', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('fetches a fully scoped account record', async () => {
    const account = { id: 42, name: 'FoxDesk' };
    (apiService.get as jest.Mock).mockResolvedValueOnce({ data: account });

    await expect(AccountService.get(42)).resolves.toEqual(account);
    expect(apiService.get).toHaveBeenCalledWith('api/v1/accounts/42');
  });

  it.each(['delete', 'undelete'] as const)('sends the %s deletion action', async actionType => {
    (apiService.post as jest.Mock).mockResolvedValueOnce({ data: {} });

    await AccountService.toggleDeletion(42, actionType);

    expect(apiService.post).toHaveBeenCalledWith('enterprise/api/v1/accounts/42/toggle_deletion', {
      action_type: actionType,
    });
  });
});
