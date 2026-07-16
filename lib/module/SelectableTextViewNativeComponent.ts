import { codegenNativeComponent, type ViewProps } from 'react-native';
import type { DirectEventHandler } from 'react-native/Libraries/Types/CodegenTypesNamespace';

export interface SelectionEvent {
  chosenOption: string;
  highlightedText: string;
}

interface NativeProps extends ViewProps {
  menuOptions: readonly string[];
  onSelection?: DirectEventHandler<SelectionEvent>;
}

export default codegenNativeComponent<NativeProps>('SelectableTextView');
