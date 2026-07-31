import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Text, View } from 'react-native';

import { Button } from '@/components-next';
import i18n from '@/i18n';
import {
  AccountService,
  type AccountDeletionAction,
  type AccountDetails,
} from '@/store/account/accountService';
import { tailwind } from '@/theme';
import { showToast } from '@/utils/toastUtils';

type AccountDeletionProps = {
  accountId: number;
  accountName: string;
};

export const AccountDeletion = ({ accountId, accountName }: AccountDeletionProps) => {
  const [account, setAccount] = useState<AccountDetails | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  const loadAccount = useCallback(async () => {
    setIsLoading(true);
    try {
      setAccount(await AccountService.get(accountId));
    } catch {
      setAccount(null);
    } finally {
      setIsLoading(false);
    }
  }, [accountId]);

  useEffect(() => {
    loadAccount();
  }, [loadAccount]);

  const deletionDate = account?.custom_attributes?.marked_for_deletion_at;
  const formattedDeletionDate = useMemo(
    () => (deletionDate ? new Date(deletionDate).toLocaleString() : ''),
    [deletionDate],
  );

  const toggleDeletion = async (actionType: AccountDeletionAction) => {
    setIsLoading(true);
    try {
      await AccountService.toggleDeletion(accountId, actionType);
      setAccount(await AccountService.get(accountId));
      showToast({
        message: i18n.t(
          actionType === 'delete'
            ? 'SETTINGS.ACCOUNT_DELETION.SUCCESS'
            : 'SETTINGS.ACCOUNT_DELETION.CANCEL_SUCCESS',
        ),
      });
    } catch {
      return;
    } finally {
      setIsLoading(false);
    }
  };

  const confirmDeletion = () => {
    Alert.alert(
      i18n.t('SETTINGS.ACCOUNT_DELETION.CONFIRM_TITLE'),
      i18n.t('SETTINGS.ACCOUNT_DELETION.CONFIRM_MESSAGE', { accountName }),
      [
        { text: i18n.t('SETTINGS.ACCOUNT_DELETION.KEEP_BUTTON'), style: 'cancel' },
        {
          text: i18n.t('SETTINGS.ACCOUNT_DELETION.DELETE_BUTTON'),
          style: 'destructive',
          onPress: () => toggleDeletion('delete'),
        },
      ],
    );
  };

  if (!account) return null;

  return (
    <View style={tailwind.style('rounded-control bg-surface-subtle p-4 gap-3')}>
      <Text style={tailwind.style('text-base font-inter-580-24 text-ink')}>
        {i18n.t('SETTINGS.ACCOUNT_DELETION.TITLE')}
      </Text>
      <Text style={tailwind.style('text-sm font-inter-normal-20 leading-5 text-ink-muted')}>
        {deletionDate
          ? i18n.t('SETTINGS.ACCOUNT_DELETION.SCHEDULED', {
              deletionDate: formattedDeletionDate,
            })
          : i18n.t('SETTINGS.ACCOUNT_DELETION.DESCRIPTION')}
      </Text>
      <Button
        variant="secondary"
        isDestructive={!deletionDate}
        disabled={isLoading}
        text={
          isLoading
            ? i18n.t('SETTINGS.ACCOUNT_DELETION.UPDATING')
            : i18n.t(
                deletionDate
                  ? 'SETTINGS.ACCOUNT_DELETION.CANCEL_BUTTON'
                  : 'SETTINGS.ACCOUNT_DELETION.DELETE_BUTTON',
              )
        }
        handlePress={() => (deletionDate ? toggleDeletion('undelete') : confirmDeletion())}
      />
    </View>
  );
};
