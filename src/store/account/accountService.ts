import { apiService } from '@/services/APIService';
import type { Account } from '@/types/Account';

export type AccountDeletionAction = 'delete' | 'undelete';

export type AccountDetails = Account & {
  custom_attributes?: {
    marked_for_deletion_at?: string;
  };
};

export class AccountService {
  static async get(accountId: number): Promise<AccountDetails> {
    const response = await apiService.get<AccountDetails>(`api/v1/accounts/${accountId}`);
    return response.data;
  }

  static async toggleDeletion(accountId: number, actionType: AccountDeletionAction): Promise<void> {
    await apiService.post(`enterprise/api/v1/accounts/${accountId}/toggle_deletion`, {
      action_type: actionType,
    });
  }
}
