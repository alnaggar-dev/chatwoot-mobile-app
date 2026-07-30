import React from 'react';
import { Text } from 'react-native';

import { tailwind } from '@/theme';
import { NativeView } from '@/components-next/native-components';
import { Label } from '@/types';

// The meta row is the quietest tier in the cell; past two labels it starts
// competing with the message preview instead of annotating it.
const MAX_VISIBLE_LABELS = 2;

export const LabelIndicator = ({ labels, allLabels }: { labels: string[]; allLabels: Label[] }) => {
  // Driven by the conversation's own label order; `allLabels` only supplies the
  // swatch, so an unresolved label still renders rather than leaving a gap.
  const visibleLabels = React.useMemo(
    () =>
      (labels ?? []).slice(0, MAX_VISIBLE_LABELS).map(title => ({
        title,
        color: allLabels?.find(label => label.title === title)?.color,
      })),
    [labels, allLabels],
  );

  if (visibleLabels.length === 0) {
    return null;
  }

  return (
    <NativeView style={tailwind.style('flex-row items-center gap-2 flex-shrink')}>
      {visibleLabels.map(({ title, color }) => (
        <NativeView key={title} style={tailwind.style('flex-row items-center gap-1 flex-shrink')}>
          <NativeView
            style={tailwind.style(
              'h-1.5 w-1.5 rounded-full',
              color ? `bg-[${color}]` : 'bg-gray-700',
            )}
          />
          <Text
            numberOfLines={1}
            style={tailwind.style('text-xs font-inter-normal-20 text-ink-muted flex-shrink')}>
            {title}
          </Text>
        </NativeView>
      ))}
    </NativeView>
  );
};
