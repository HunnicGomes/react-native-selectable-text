import React, { useRef, useEffect } from 'react';
import type { ViewStyle, NativeSyntheticEvent } from 'react-native';
import { Platform, findNodeHandle, DeviceEventEmitter } from 'react-native';
import SelectableTextViewNativeComponent, {
  type SelectionEvent,
} from './SelectableTextViewNativeComponent';

interface SelectableTextViewProps {
  children: React.ReactNode;
  menuOptions: string[];
  onSelection?: (event: SelectionEvent) => void;
  style?: ViewStyle;
}

export const SelectableTextView: React.FC<SelectableTextViewProps> = ({
  children,
  menuOptions,
  onSelection,
  style,
}) => {
  const viewRef = useRef<any>(null);

  // Android: Use DeviceEventEmitter (original working approach)
  useEffect(() => {
    if (Platform.OS === 'android' && onSelection) {
      const subscription = DeviceEventEmitter.addListener(
        'SelectableTextSelection',
        (eventData: {
          viewTag: number;
          chosenOption: string;
          highlightedText: string;
        }) => {
          const viewTag = findNodeHandle(viewRef.current);
          if (viewTag === eventData.viewTag) {
            onSelection({
              chosenOption: eventData.chosenOption,
              highlightedText: eventData.highlightedText,
            });
          }
        }
      );

      return () => subscription.remove();
    }
    return () => {};
  }, [onSelection]);

  // iOS: Use DirectEventHandler (current approach)
  const handleSelection = (event: NativeSyntheticEvent<SelectionEvent>) => {
    if (Platform.OS === 'ios' && onSelection) {
      onSelection(event.nativeEvent);
    }
  };

  return (
    <SelectableTextViewNativeComponent
      ref={viewRef}
      style={style}
      menuOptions={menuOptions}
      onSelection={Platform.OS === 'ios' ? handleSelection : undefined}
    >
      {children}
    </SelectableTextViewNativeComponent>
  );
};
