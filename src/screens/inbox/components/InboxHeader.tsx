import React from 'react';
import { Pressable } from 'react-native';
import Animated from 'react-native-reanimated';
import { BottomSheetModal, useBottomSheetSpringConfigs } from '@gorhom/bottom-sheet';

import { BottomSheetBackdrop, BottomSheetWrapper } from '@/components-next';

import { Icon } from '@/components-next/common/icon';
import { DoubleCheckIcon, InboxFilterIcon } from '@/svg-icons';
import { tailwind } from '@/theme';
import { InboxFilters } from './InboxFilters';
import i18n from '@/i18n';
import { useRefsContext } from '@/context';

type InboxHeaderProps = {
  markAllAsRead: () => void;
};

export const InboxHeader = (props: InboxHeaderProps) => {
  const { markAllAsRead } = props;
  const { inboxFiltersSheetRef } = useRefsContext();
  const handleToggleState = () => {
    inboxFiltersSheetRef.current?.present();
  };

  const animationConfigs = useBottomSheetSpringConfigs({
    mass: 1,
    stiffness: 420,
    damping: 30,
  });

  return (
    <Animated.View style={tailwind.style('border-b-[1px] border-b-blackA-A3')}>
      <Animated.View
        style={tailwind.style('flex flex-row items-center justify-between gap-4 px-4 pt-4 pb-3')}>
        <Animated.Text
          numberOfLines={1}
          style={tailwind.style('flex-1 text-3xl font-inter-semibold-20 text-ink')}>
          {i18n.t('NOTIFICATION.INBOX')}
        </Animated.Text>
        <Animated.View style={tailwind.style('flex flex-row items-center gap-5')}>
          <Pressable hitSlop={16} onPress={markAllAsRead}>
            <Icon icon={<DoubleCheckIcon />} size={24} />
          </Pressable>
          <Pressable onPress={handleToggleState} hitSlop={16}>
            <Icon icon={<InboxFilterIcon />} size={24} />
          </Pressable>
        </Animated.View>
      </Animated.View>
      <BottomSheetModal
        ref={inboxFiltersSheetRef}
        backdropComponent={BottomSheetBackdrop}
        handleIndicatorStyle={tailwind.style('overflow-hidden bg-blackA-A6 w-8 h-1 rounded-[11px]')}
        handleStyle={tailwind.style('p-0 h-4 pt-[5px]')}
        style={tailwind.style('rounded-[26px] overflow-hidden')}
        animationConfigs={animationConfigs}
        enablePanDownToClose
        snapPoints={[160]}>
        <BottomSheetWrapper>
          <InboxFilters />
        </BottomSheetWrapper>
      </BottomSheetModal>
    </Animated.View>
  );
};
