import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Text } from 'react-native';

import { tailwind } from '@/theme';
import { NativeView } from '@/components-next/native-components';
import { SlaMissedIcon } from '@/svg-icons';
import { SLA, SLAStatus } from '@/types/common/SLA';
import { evaluateSLAStatus } from '@chatwoot/utils';
import i18n from '@/i18n';

const REFRESH_INTERVAL = 60000;

export const SLAIndicator = ({
  slaPolicyId,
  appliedSla,
  appliedSlaConversationDetails,
  onSLAStatusChange,
}: {
  slaPolicyId: number;
  appliedSla: SLA;
  appliedSlaConversationDetails: {
    firstReplyCreatedAt: number;
    waitingSince: number;
    status: string;
  };
  onSLAStatusChange: (hasThreshold: boolean) => void;
}) => {
  const [slaStatus, setSlaStatus] = useState<SLAStatus | null>(null);

  const timerRef = useRef<NodeJS.Timeout | null>(null);

  const updateSlaStatus = useCallback(() => {
    const status = evaluateSLAStatus({
      appliedSla: {
        id: appliedSla.id,
        name: appliedSla.slaName,
        description: appliedSla.slaDescription,
        sla_first_response_time_threshold: appliedSla.slaFirstResponseTimeThreshold,
        sla_next_response_time_threshold: appliedSla.slaNextResponseTimeThreshold,
        sla_resolution_time_threshold: appliedSla.slaResolutionTimeThreshold,
        only_during_business_hours: appliedSla.slaOnlyDuringBusinessHours,
        created_at: appliedSla.createdAt,
      },
      // eslint-disable-next-line @typescript-eslint/ban-ts-comment
      // @ts-ignore
      chat: {
        first_reply_created_at: appliedSlaConversationDetails.firstReplyCreatedAt,
        waiting_since: appliedSlaConversationDetails.waitingSince,
        status: appliedSlaConversationDetails.status,
      },
    });
    setSlaStatus(status);
    onSLAStatusChange(status?.threshold ? true : false);
  }, [appliedSla, appliedSlaConversationDetails, onSLAStatusChange]);

  const createTimer = useCallback(() => {
    timerRef.current = setTimeout(() => {
      updateSlaStatus();
      createTimer();
    }, REFRESH_INTERVAL);
  }, [updateSlaStatus]);

  useEffect(() => {
    createTimer();
    updateSlaStatus();
    return () => {
      if (timerRef.current) {
        clearTimeout(timerRef.current);
      }
    };
  }, [createTimer, updateSlaStatus]);

  if (!slaStatus?.threshold) {
    return null;
  }

  const sLAStatusText = () => {
    const upperCaseType = slaStatus?.type?.toUpperCase(); // FRT, NRT, or RT
    return i18n.t(`SLA.${upperCaseType}`);
  };

  const isSlaMissed = !!slaStatus?.isSlaMissed;

  return (
    <NativeView style={tailwind.style('flex-row items-center gap-1 flex-shrink')}>
      {/* A missed SLA is the one alarming element the row is allowed; an
          on-track one stays plain text in the quiet meta tier. */}
      {isSlaMissed && <SlaMissedIcon color={tailwind.color('text-ruby-800') as string} />}
      <Text
        numberOfLines={1}
        style={tailwind.style(
          'text-xs font-inter-normal-20 flex-shrink',
          isSlaMissed ? 'text-ruby-800' : 'text-ink-muted',
        )}>
        {`${sLAStatusText()}: ${slaStatus?.threshold}`}
      </Text>
    </NativeView>
  );
};
