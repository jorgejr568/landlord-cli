MAX_CENTAVOS = 2_147_483_647


def total_centavos(amounts: list[int]) -> int:
    total = sum(amounts)
    if total > MAX_CENTAVOS:
        raise ValueError("O valor total deve ser de no máximo R$ 21.474.836,47.")
    return total
