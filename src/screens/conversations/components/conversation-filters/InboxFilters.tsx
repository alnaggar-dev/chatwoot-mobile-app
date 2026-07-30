import React from 'react';
import { Pressable } from 'react-native';
import Animated from 'react-native-reanimated';
import { BottomSheetScrollView } from '@gorhom/bottom-sheet';

import { useRefsContext } from '@/context';
import { tailwind } from '@/theme';
import { useHaptic } from '@/utils';
import { BottomSheetHeader, Icon } from '@/components-next/common';
import { selectFilters, setFilters } from '@/store/conversation/conversationFilterSlice';
import { useAppDispatch, useAppSelector } from '@/hooks';
import { selectAllInboxes } from '@/store/inbox/inboxSelectors';
import { getChannelIcon } from '@/utils';
import { Channel } from '@/types';
import i18n from '@/i18n';

type InboxCellProps = {
  value: { id: number; name: string; channelType: Channel; medium: string };
};

const InboxCell = (props: InboxCellProps) => {
  const { filtersModalSheetRef } = useRefsContext();
  const dispatch = useAppDispatch();
  const { value } = props;

  const filters = useAppSelector(selectFilters);
  const hapticSelection = useHaptic();

  const isActive = filters.inbox_id === value.id.toString();

  const handlePreferredAssigneeTypePress = () => {
    hapticSelection?.();
    dispatch(setFilters({ key: 'inbox_id', value: value.id.toString() }));
    setTimeout(() => filtersModalSheetRef.current?.dismiss({ overshootClamping: true }), 1);
  };

  return (
    <Pressable
      style={tailwind.style('min-h-[44px] justify-center')}
      onPress={handlePreferredAssigneeTypePress}>
      <Animated.View
        style={tailwind.style(
          'flex flex-row items-center py-1.5 px-3 rounded-full border',
          isActive ? 'bg-brand-subtle border-brand-muted' : 'bg-surface-subtle border-outline-soft',
        )}>
        <Icon
          icon={getChannelIcon(value.channelType, value.medium, '')}
          size={14}
          style={tailwind.style('mr-1.5 flex items-center justify-center')}
        />
        <Animated.Text
          style={tailwind.style(
            'text-cxs leading-[16px] tracking-[0.24px] capitalize',
            isActive
              ? 'font-inter-semibold-20 text-brand'
              : 'font-inter-medium-24 text-ink-secondary',
          )}>
          {value.name}
        </Animated.Text>
      </Animated.View>
    </Pressable>
  );
};

export const InboxFilters = () => {
  const inboxes = useAppSelector(selectAllInboxes);
  const inboxList = [
    {
      id: 0,
      name: i18n.t('FILTER.ALL_INBOXES'),
      channelType: 'Channel::All' as Channel,
      avatarUrl: '',
      channelId: 0,
      phoneNumber: '',
      medium: 'Channel::All',
      provider: 'Channel::All',
    },
    ...inboxes,
  ].map(inbox => ({
    id: inbox.id,
    name: inbox.name,
    channelType: inbox.channelType as Channel,
    medium: inbox.medium,
  }));

  return (
    <BottomSheetScrollView
      contentContainerStyle={tailwind.style('pb-4')}
      stickyHeaderIndices={[0]}
      showsVerticalScrollIndicator={true}>
      <Animated.View style={tailwind.style('bg-surface pb-3')}>
        <BottomSheetHeader headerText={i18n.t('CONVERSATION.FILTERS.INBOX.TITLE')} />
      </Animated.View>
      <Animated.View style={tailwind.style('flex flex-row flex-wrap gap-2 px-4 pt-1')}>
        {inboxList.map((value, index) => (
          <InboxCell key={index} {...{ value }} />
        ))}
      </Animated.View>
    </BottomSheetScrollView>
  );
};
