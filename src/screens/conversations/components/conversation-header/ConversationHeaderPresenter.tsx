import React from 'react';
import { Pressable, Text, ViewStyle } from 'react-native';
import Animated, { AnimatedStyle } from 'react-native-reanimated';
import { Icon } from '@/components-next/common';
import { CheckedIcon, CloseIcon, FilterIcon, UncheckedIcon, SearchIcon } from '@/svg-icons';
import { tailwind } from '@/theme';
import i18n from '@/i18n';
import { useScaleAnimation } from '@/utils';
import { useHeaderAnimation } from '@/hooks/useHeaderAnimation';

type HeaderState = 'Search' | 'Filter' | 'Select' | 'none';

type ConversationHeaderPresenterProps = {
  currentState: HeaderState;
  isSelectedAll: boolean;
  filtersAppliedCount: number;
  onLeftIconPress: () => void;
  onRightIconPress: () => void;
  onClearFilter: () => void;
};

type SearchOrSelectAllActionProps = {
  currentState: HeaderState;
  isSelectedAll: boolean;
  onLeftIconPress: () => void;
};

type ClearFilterActionProps = {
  filtersAppliedCount: number;
  onClearFilter: () => void;
  handlers: Record<string, unknown>;
  animatedStyle: ViewStyle | AnimatedStyle<ViewStyle>;
};

type FilterOrCloseActionProps = {
  currentState: HeaderState;
  filtersAppliedCount: number;
  onRightIconPress: () => void;
};

const SearchOrSelectAllAction = ({
  currentState,
  isSelectedAll,
  onLeftIconPress,
}: SearchOrSelectAllActionProps) => {
  const { entering, exiting } = useHeaderAnimation();

  if (currentState === 'Filter' || currentState === 'Search') return null;
  if (currentState !== 'Select') {
    return (
      <Pressable onPress={onLeftIconPress} hitSlop={16}>
        <Animated.View exiting={exiting} entering={entering}>
          <Icon size={24} icon={<SearchIcon stroke={tailwind.color('text-ink-secondary')} />} />
        </Animated.View>
      </Pressable>
    );
  }

  return (
    <Pressable onPress={onLeftIconPress} hitSlop={16}>
      <Animated.View exiting={exiting} entering={entering}>
        <Icon
          size={24}
          icon={
            isSelectedAll ? (
              <CheckedIcon />
            ) : (
              <UncheckedIcon stroke={tailwind.color('text-ink-secondary')} />
            )
          }
        />
      </Animated.View>
    </Pressable>
  );
};

const ClearFilterAction = ({
  filtersAppliedCount,
  onClearFilter,
  handlers,
  animatedStyle,
}: ClearFilterActionProps) => {
  const { entering, exiting } = useHeaderAnimation();

  return (
    <Animated.View style={animatedStyle} exiting={exiting} entering={entering}>
      <Pressable onPress={onClearFilter} disabled={filtersAppliedCount === 0} {...handlers}>
        <Text
          style={tailwind.style(
            'text-md font-inter-medium-24 leading-[17px] tracking-[0.24px]',
            filtersAppliedCount === 0 ? 'text-ink-muted' : 'text-brand',
          )}>
          {i18n.t('CONVERSATION.HEADER.CLEAR_FILTER')}
          {filtersAppliedCount > 0 ? ` (${filtersAppliedCount})` : ''}
        </Text>
      </Pressable>
    </Animated.View>
  );
};

const FilterOrCloseAction = ({
  currentState,
  filtersAppliedCount,
  onRightIconPress,
}: FilterOrCloseActionProps) => {
  const { entering, exiting } = useHeaderAnimation();

  return (
    <Pressable onPress={onRightIconPress} hitSlop={16}>
      {currentState === 'Filter' || currentState === 'Select' ? (
        <Animated.View exiting={exiting} entering={entering}>
          <Icon size={24} icon={<CloseIcon />} />
        </Animated.View>
      ) : (
        <Animated.View exiting={exiting} entering={entering}>
          {filtersAppliedCount > 0 && (
            <Animated.View
              style={tailwind.style(
                'absolute z-10 -right-0.5 h-2.5 w-2.5 rounded-full bg-brand-vivid',
              )}
            />
          )}
          <Icon size={24} icon={<FilterIcon />} />
        </Animated.View>
      )}
    </Pressable>
  );
};

export const ConversationHeaderPresenter = ({
  currentState,
  isSelectedAll,
  filtersAppliedCount,
  onLeftIconPress,
  onRightIconPress,
  onClearFilter,
}: ConversationHeaderPresenterProps) => {
  const { handlers, animatedStyle } = useScaleAnimation();

  return (
    <Animated.View style={tailwind.style('px-4 pt-4 pb-3')}>
      <Animated.View style={tailwind.style('flex flex-row items-center justify-between gap-4')}>
        <Text
          numberOfLines={1}
          style={tailwind.style('flex-1 text-3xl font-inter-semibold-20 text-ink')}>
          {i18n.t('CONVERSATION.HEADER.TITLE')}
        </Text>
        <Animated.View style={tailwind.style('flex flex-row items-center gap-5')}>
          {currentState === 'Filter' && (
            <ClearFilterAction
              filtersAppliedCount={filtersAppliedCount}
              onClearFilter={onClearFilter}
              handlers={handlers}
              animatedStyle={animatedStyle}
            />
          )}
          <SearchOrSelectAllAction
            currentState={currentState}
            isSelectedAll={isSelectedAll}
            onLeftIconPress={onLeftIconPress}
          />
          <FilterOrCloseAction
            currentState={currentState}
            filtersAppliedCount={filtersAppliedCount}
            onRightIconPress={onRightIconPress}
          />
        </Animated.View>
      </Animated.View>
    </Animated.View>
  );
};
