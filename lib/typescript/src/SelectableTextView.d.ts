import React from 'react';
import type { ViewStyle } from 'react-native';
import { type SelectionEvent } from './SelectableTextViewNativeComponent';
interface SelectableTextViewProps {
    children: React.ReactNode;
    menuOptions: string[];
    onSelection?: (event: SelectionEvent) => void;
    style?: ViewStyle;
}
export declare const SelectableTextView: React.FC<SelectableTextViewProps>;
export {};
//# sourceMappingURL=SelectableTextView.d.ts.map