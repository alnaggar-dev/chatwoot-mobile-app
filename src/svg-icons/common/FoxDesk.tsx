import React from 'react';
import { Path, Svg } from 'react-native-svg';

import { IconProps } from '../../types';

export const FoxDeskIcon = ({ stroke = '#858585', strokeWidth = 1.5 }: IconProps): JSX.Element => {
  return (
    <Svg width="100%" height="100%" viewBox="0 0 24 24" fill="none">
      <Path
        d="M4.5 4L7.5 7H16.5L19.5 4L20.5 10.5L12 20.5L3.5 10.5L4.5 4Z"
        stroke={stroke}
        strokeWidth={strokeWidth}
        strokeLinejoin="round"
      />
      <Path
        d="M9 11.5L10.5 12.5M15 11.5L13.5 12.5M12 15.5V16.5"
        stroke={stroke}
        strokeWidth={strokeWidth}
        strokeLinecap="round"
      />
    </Svg>
  );
};
