import { ChevronLeft } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router";

import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import { normalizedFieldErrors } from "../../lib/api/errors";
import { useDocumentTitle } from "../../lib/useDocumentTitle";
import { pushAnalyticsFromResponse } from "../auth/analytics";
import { OrganizationForm, type OrganizationValues } from "./OrganizationForm";

const EMPTY_VALUES: OrganizationValues = {
  name: "",
  pix_key: "",
  pix_merchant_city: "",
  pix_merchant_name: ""
};

export function OrganizationCreatePage() {
  const navigate = useNavigate();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const createRef = useRef<AbortController | null>(null);

  useDocumentTitle("Nova organização - Rentivo");
  useEffect(() => () => {
    createRef.current?.abort();
    createRef.current = null;
  }, []);

  const submit = async (values: OrganizationValues) => {
    if (createRef.current) return;
    const controller = new AbortController();
    createRef.current = controller;
    const whileCurrent = (action: () => void) => {
      if (createRef.current === controller) action();
    };
    setSaving(true);
    setError("");
    setFieldErrors({});
    try {
      const { data, response } = await apiRequest(apiClient.POST("/api/v1/organizations", {
        body: {
          name: values.name.trim(),
          pix_key: "",
          pix_merchant_city: "",
          pix_merchant_name: ""
        },
        signal: controller.signal
      }));
      whileCurrent(() => {
        pushAnalyticsFromResponse(response);
        navigate(`/organizations/${data.uuid}`);
      });
    } catch (caught) {
      whileCurrent(() => {
        if (caught instanceof ApiError) {
          setError(Object.keys(caught.fields).length ? "" : caught.message);
          setFieldErrors(normalizedFieldErrors(caught));
        } else {
          setError("Não foi possível criar a organização.");
        }
      });
    } finally {
      whileCurrent(() => {
        createRef.current = null;
        setSaving(false);
      });
    }
  };

  return (
    <>
      <Link className="crumb" to="/organizations/">
        <ChevronLeft aria-hidden="true" size={16} strokeWidth={2.5} />
        Organizações
      </Link>
      <div className="pagehead">
        <div>
          <h1 className="pagehead__title">Nova organização</h1>
          <p className="pagehead__sub">Crie um espaço compartilhado para gerenciar imóveis com sua equipe.</p>
        </div>
      </div>
      <OrganizationForm error={error} fieldErrors={fieldErrors} mode="create" onSubmit={(values) => void submit(values)} saving={saving} values={EMPTY_VALUES} />
    </>
  );
}
