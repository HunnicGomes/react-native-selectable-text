"use strict";

import React, { useRef, useEffect } from 'react';
import { Platform, findNodeHandle, DeviceEventEmitter } from 'react-native';
import SelectableTextViewNativeComponent from './SelectableTextViewNativeComponent';
import { jsx as _jsx } from "react/jsx-runtime";
export const SelectableTextView = ({
  children,
  menuOptions,
  onSelection,
  style
}) => {
  const viewRef = useRef(null);

  // Android: Use DeviceEventEmitter (original working approach)
  useEffect(() => {
    if (Platform.OS === 'android' && onSelection) {
      const subscription = DeviceEventEmitter.addListener('SelectableTextSelection', eventData => {
        const viewTag = findNodeHandle(viewRef.current);
        if (viewTag === eventData.viewTag) {
          onSelection({
            chosenOption: eventData.chosenOption,
            highlightedText: eventData.highlightedText
          });
        }
      });
      return () => subscription.remove();
    }
    return () => {};
  }, [onSelection]);

  // iOS: Use DirectEventHandler (current approach)
  const handleSelection = event => {
    if (Platform.OS === 'ios' && onSelection) {
      onSelection(event.nativeEvent);
    }
  };
  return /*#__PURE__*/_jsx(SelectableTextViewNativeComponent, {
    ref: viewRef,
    style: style,
    menuOptions: menuOptions,
    onSelection: Platform.OS === 'ios' ? handleSelection : undefined,
    children: children
  });
};
//# sourceMappingURL=SelectableTextView.js.map