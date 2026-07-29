import { RouterProvider } from "react-router";

import { appRouter } from "./router";
import { AppProviders } from "./providers";

export function App() {
  return (
    <AppProviders>
      <RouterProvider router={appRouter} />
    </AppProviders>
  );
}
