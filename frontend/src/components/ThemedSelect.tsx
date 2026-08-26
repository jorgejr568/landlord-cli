import * as SelectPrimitive from "@radix-ui/react-select";
import { Check, ChevronDown, ChevronUp } from "lucide-react";
import {
  forwardRef,
  useMemo,
  type AriaAttributes,
  type FocusEventHandler
} from "react";

export interface SelectOption {
  disabled?: boolean;
  label: string;
  value: string;
}

export interface ThemedSelectProps {
  "aria-describedby"?: AriaAttributes["aria-describedby"];
  "aria-invalid"?: AriaAttributes["aria-invalid"];
  "aria-label"?: AriaAttributes["aria-label"];
  "aria-labelledby"?: AriaAttributes["aria-labelledby"];
  className?: string;
  disabled?: boolean;
  id?: string;
  name?: string;
  onBlur?: FocusEventHandler<HTMLButtonElement>;
  onFocus?: FocusEventHandler<HTMLButtonElement>;
  onValueChange: (value: string) => void;
  options: SelectOption[];
  placeholder?: string;
  required?: boolean;
  value: string;
}

function emptyValueFor(options: SelectOption[]): string {
  let sentinel = "__rentivo_empty_value__";
  const values = new Set(options.map((option) => option.value));
  while (values.has(sentinel)) sentinel += "_";
  return sentinel;
}

export const ThemedSelect = forwardRef<HTMLButtonElement, ThemedSelectProps>(function ThemedSelect({
  "aria-describedby": ariaDescribedBy,
  "aria-invalid": ariaInvalid,
  "aria-label": ariaLabel,
  "aria-labelledby": ariaLabelledBy,
  className = "",
  disabled = false,
  id,
  name,
  onBlur,
  onFocus,
  onValueChange,
  options,
  placeholder,
  required = false,
  value
}, ref) {
  const emptyValue = useMemo(() => emptyValueFor(options), [options]);
  const hasEmptyOption = options.some((option) => option.value === "");
  const radixValue = value === "" && hasEmptyOption ? emptyValue : value;
  const selectedOption = options.find((option) => option.value === value);

  return (
    <>
      <SelectPrimitive.Root
        disabled={disabled}
        onValueChange={(nextValue) => onValueChange(nextValue === emptyValue ? "" : nextValue)}
        required={required}
        value={radixValue}
      >
        <SelectPrimitive.Trigger
          aria-describedby={ariaDescribedBy}
          aria-invalid={ariaInvalid}
          aria-label={ariaLabel}
          aria-labelledby={ariaLabelledBy}
          className={`themed-select__trigger${className ? ` ${className}` : ""}`}
          id={id}
          name={name}
          onBlur={onBlur}
          onFocus={onFocus}
          ref={ref}
          title={selectedOption?.label}
          value={value}
        >
          <span className="themed-select__value"><SelectPrimitive.Value placeholder={placeholder} /></span>
          <SelectPrimitive.Icon asChild>
            <ChevronDown aria-hidden="true" className="themed-select__chevron" size={16} strokeWidth={2.5} />
          </SelectPrimitive.Icon>
        </SelectPrimitive.Trigger>

        <SelectPrimitive.Portal>
          <SelectPrimitive.Content
            className="themed-select__content"
            collisionPadding={12}
            position="popper"
            sideOffset={5}
          >
            <SelectPrimitive.ScrollUpButton className="themed-select__scroll-button">
              <ChevronUp aria-hidden="true" size={15} strokeWidth={2.5} />
            </SelectPrimitive.ScrollUpButton>
            <SelectPrimitive.Viewport className="themed-select__viewport">
              {options.map((option) => (
                <SelectPrimitive.Item
                  className="themed-select__item"
                  disabled={option.disabled}
                  key={option.value}
                  value={option.value === "" ? emptyValue : option.value}
                >
                  <span className="themed-select__indicator" aria-hidden="true">
                    <SelectPrimitive.ItemIndicator>
                      <Check size={14} strokeWidth={3} />
                    </SelectPrimitive.ItemIndicator>
                  </span>
                  <SelectPrimitive.ItemText>{option.label}</SelectPrimitive.ItemText>
                </SelectPrimitive.Item>
              ))}
            </SelectPrimitive.Viewport>
            <SelectPrimitive.ScrollDownButton className="themed-select__scroll-button">
              <ChevronDown aria-hidden="true" size={15} strokeWidth={2.5} />
            </SelectPrimitive.ScrollDownButton>
          </SelectPrimitive.Content>
        </SelectPrimitive.Portal>
      </SelectPrimitive.Root>
      {name ? <input disabled={disabled} name={name} type="hidden" value={value} /> : null}
    </>
  );
});
