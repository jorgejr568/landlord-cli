import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useRef, useState } from "react";
import { vi } from "vitest";

import { ThemedSelect, type SelectOption } from "./ThemedSelect";

const OPTIONS: SelectOption[] = [
  { label: "Minha conta", value: "" },
  { label: "Edifício Aurora", value: "aurora" },
  { label: "Residencial Ipê", value: "ipe" }
];

function ControlledSelect({ initialValue = "" }: { initialValue?: string }) {
  const [value, setValue] = useState(initialValue);
  return (
    <>
      <label htmlFor="owner">Proprietário</label>
      <p id="owner-hint">Responsável pelo recebimento.</p>
      <ThemedSelect
        aria-describedby="owner-hint"
        id="owner"
        name="owner"
        onValueChange={setValue}
        options={OPTIONS}
        required
        value={value}
      />
      <output>{value || "personal"}</output>
      <button onClick={() => setValue("ipe")} type="button">Escolher Ipê externamente</button>
    </>
  );
}

describe("ThemedSelect", () => {
  it("associates its trigger with a label and description", () => {
    render(<ControlledSelect initialValue="aurora" />);

    const trigger = screen.getByRole("combobox", { name: "Proprietário" });
    expect(trigger).toHaveAttribute("id", "owner");
    expect(trigger).toHaveAttribute("aria-describedby", "owner-hint");
    expect(trigger).toHaveAttribute("aria-required", "true");
    expect(trigger).toHaveTextContent("Edifício Aurora");
  });

  it("opens and selects an option while remaining controlled", async () => {
    const user = userEvent.setup();
    render(<ControlledSelect initialValue="aurora" />);

    const trigger = screen.getByRole("combobox", { name: "Proprietário" });
    await user.click(trigger);
    await user.click(screen.getByRole("option", { name: "Residencial Ipê" }));

    expect(trigger).toHaveTextContent("Residencial Ipê");
    expect(screen.getByText("ipe", { selector: "output" })).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Escolher Ipê externamente" }));
    expect(trigger).toHaveTextContent("Residencial Ipê");
  });

  it("supports a placeholder and preserves a long option's full accessible text", async () => {
    const user = userEvent.setup();
    const longLabel = "Condomínio Parque das Araucárias, Bloco Norte, apartamento 1204";
    const { rerender } = render(
      <ThemedSelect
        aria-label="Cobrança para transferir"
        id="billing"
        onValueChange={() => undefined}
        options={[{ label: longLabel, value: "long" }]}
        placeholder="Escolha uma cobrança"
        value=""
      />
    );

    const trigger = screen.getByRole("combobox", { name: "Cobrança para transferir" });
    expect(trigger).toHaveTextContent("Escolha uma cobrança");

    await user.click(trigger);
    expect(screen.getByRole("option", { name: longLabel })).toHaveTextContent(longLabel);

    rerender(
      <ThemedSelect
        aria-label="Cobrança para transferir"
        id="billing"
        onValueChange={() => undefined}
        options={[{ label: longLabel, value: "long" }]}
        placeholder="Escolha uma cobrança"
        value="long"
      />
    );
    expect(trigger).toHaveTextContent(longLabel);
    expect(trigger).toHaveAttribute("title", longLabel);
  });

  it("prevents interaction when disabled", async () => {
    const user = userEvent.setup();
    render(
      <ThemedSelect
        aria-label="Papel"
        disabled
        id="role"
        onValueChange={() => undefined}
        options={OPTIONS}
        value="aurora"
      />
    );
    const trigger = screen.getByRole("combobox", { name: "Papel" });
    expect(trigger).toBeDisabled();
    await user.click(trigger);
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
  });

  it("keeps an empty option distinct when another option uses the sentinel value", async () => {
    const user = userEvent.setup();
    const onValueChange = vi.fn();
    render(
      <ThemedSelect
        aria-label="Proprietário"
        onValueChange={onValueChange}
        options={[
          { label: "Minha conta", value: "" },
          { label: "Valor reservado", value: "__rentivo_empty_value__" }
        ]}
        value=""
      />
    );

    const trigger = screen.getByRole("combobox", { name: "Proprietário" });
    expect(trigger).toHaveTextContent("Minha conta");
    await user.click(trigger);
    await user.click(screen.getByRole("option", { name: "Valor reservado" }));
    expect(onValueChange).toHaveBeenCalledWith("__rentivo_empty_value__");
  });

  it("exposes a focus-compatible trigger ref", async () => {
    const user = userEvent.setup();

    function RefHarness() {
      const ref = useRef<HTMLButtonElement>(null);
      return (
        <>
          <ThemedSelect aria-label="Papel" id="role" onValueChange={() => undefined} options={OPTIONS} ref={ref} value="aurora" />
          <button onClick={() => ref.current?.focus()} type="button">Focar papel</button>
        </>
      );
    }

    render(<RefHarness />);
    const trigger = screen.getByRole("combobox", { name: "Papel" });
    await user.click(screen.getByRole("button", { name: "Focar papel" }));
    expect(trigger).toHaveFocus();
  });

  it("submits its public name and value with the surrounding form", async () => {
    const user = userEvent.setup();
    let submitted: FormData | undefined;
    render(
      <form onSubmit={(event) => { event.preventDefault(); submitted = new FormData(event.currentTarget); }}>
        <ControlledSelect initialValue="aurora" />
        <button type="submit">Salvar</button>
      </form>
    );

    await user.click(screen.getByRole("button", { name: "Salvar" }));
    expect(submitted?.get("owner")).toBe("aurora");
    expect(submitted?.getAll("owner")).toEqual(["aurora"]);
  });

  it("supports keyboard opening and selection", async () => {
    const user = userEvent.setup();
    render(<ControlledSelect initialValue="aurora" />);

    const trigger = screen.getByRole("combobox", { name: "Proprietário" });
    trigger.focus();
    await user.keyboard("{ArrowDown}{ArrowDown}{Enter}");

    expect(trigger).toHaveTextContent("Residencial Ipê");
    expect(screen.getByText("ipe", { selector: "output" })).toBeInTheDocument();
  });
});
