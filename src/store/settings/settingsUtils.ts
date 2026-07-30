import { showToast } from '@/utils/toastUtils';
import I18n from '@/i18n';

export const handleApiError = (error: unknown, customErrorMsg?: string) => {
  const errorMessage = error instanceof Error ? error.message : I18n.t('CONFIGURE_URL.ERROR');
  showToast({ message: errorMessage });
  return errorMessage;
};
