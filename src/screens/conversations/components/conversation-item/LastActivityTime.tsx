import React, { useEffect, useState } from 'react';
import { StyleSheet, Text } from 'react-native';

import { tailwind } from '@/theme';
import { formatTimeToShortForm, formatRelativeTime } from '@/utils/dateTimeUtils';

// Constants from Vue component
const MINUTE_IN_MS = 60000;
const HOUR_IN_MS = MINUTE_IN_MS * 60;
const DAY_IN_MS = HOUR_IN_MS * 24;

const styles = StyleSheet.create({
  // Fixed digit advance width, so a ticking timestamp never nudges the row it
  // is right-aligned in.
  tabularNums: { fontVariant: ['tabular-nums'] },
});

type LastActivityTimeProps = {
  timestamp: number;
};

export const LastActivityTime = ({ timestamp }: LastActivityTimeProps) => {
  const [lastActivityTime, setLastActivityTime] = useState(
    formatTimeToShortForm(formatRelativeTime(timestamp)),
  );

  useEffect(() => {
    const getRefreshTime = () => {
      const timeDiff = Date.now() - timestamp * 1000;
      if (timeDiff > DAY_IN_MS) return DAY_IN_MS;
      if (timeDiff > HOUR_IN_MS) return HOUR_IN_MS;
      return MINUTE_IN_MS;
    };

    const updateTime = () => {
      setLastActivityTime(formatTimeToShortForm(formatRelativeTime(timestamp)));
    };

    const timer = setTimeout(function refresh() {
      updateTime();
      // Set up next refresh
      setTimeout(refresh, getRefreshTime());
    }, getRefreshTime());

    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <Text
      style={[tailwind.style('text-xs font-inter-normal-20 text-ink-muted'), styles.tabularNums]}>
      {lastActivityTime}
    </Text>
  );
};
