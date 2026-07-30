import React from 'react';
import Animated, { LinearTransition, withTiming } from 'react-native-reanimated';
import { tailwind } from '@/theme';
import { FilterButton } from './FilterButton';
import i18n from '@/i18n';

// Generic type for filter options
export type BaseFilterOption = {
  type: string;
  options: Record<string, string>;
  defaultFilter: string;
};

type FilterBarProps = {
  allFilters: BaseFilterOption[];
  selectedFilters: Record<string, string>;
  onFilterPress: (type: string) => void;
};

export const FilterBar = ({ allFilters, selectedFilters, onFilterPress }: FilterBarProps) => {
  // Row Exit Animation
  const exiting = () => {
    'worklet';
    const animations = {
      opacity: withTiming(0, { duration: 250 }),
    };
    const initialValues = {
      opacity: 1,
    };
    return {
      initialValues,
      animations,
    };
  };

  const getFilterTitle = (value: BaseFilterOption) => {
    return i18n.t(
      `CONVERSATION.FILTERS.${value.type.toUpperCase()}.OPTIONS.${selectedFilters[value.type].toUpperCase()}`,
    );
  };

  // A chip is active once the filter has been narrowed away from its declared default.
  const isFilterActive = (value: BaseFilterOption) =>
    value.options[selectedFilters[value.type] as keyof typeof value.options] !==
    value.defaultFilter;

  return (
    <Animated.View
      exiting={exiting}
      style={tailwind.style('px-3 h-[50px] flex flex-row items-center')}>
      {allFilters.map((value, index) => {
        if (value.type === 'inbox_id') {
          return (
            <Animated.View
              layout={LinearTransition.springify().stiffness(200).damping(24)}
              key={index}
              style={tailwind.style('pr-2')}>
              <FilterButton
                handleOnPress={() => onFilterPress(value.type)}
                isActive={isFilterActive(value)}
                value={value.options[selectedFilters[value.type] as keyof typeof value.options]}
              />
            </Animated.View>
          );
        }
        return (
          <Animated.View
            layout={LinearTransition.springify().stiffness(200).damping(24)}
            key={index}
            style={tailwind.style('pr-2')}>
            <FilterButton
              handleOnPress={() => onFilterPress(value.type)}
              isActive={isFilterActive(value)}
              value={getFilterTitle(value)}
            />
          </Animated.View>
        );
      })}
    </Animated.View>
  );
};
