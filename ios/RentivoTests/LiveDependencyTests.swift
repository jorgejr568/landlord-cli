import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@MainActor
@Test func liveDependenciesUseTheProductionStoreForEveryRepository() {
  let store = APIRentivoStore(inMemoryCredentialStore: true)
  let dependencies = AppDependencies.live(store: store)

  #expect(dependencies.auth === store)
  #expect(dependencies.billings === store)
  #expect(dependencies.organizations === store)
  #expect(dependencies.downloads === store)
  #expect(dependencies.exports === store)

  // Callers must never need to know the concrete store: everything the app branches on is
  // declared by the protocols, so `usesLiveAPI` is what separates this wiring from
  // `AppDependencies.mock`. Demo settings stay on a separate inert repository.
  #expect(dependencies.auth.usesLiveAPI)
  #expect(AppDependencies.mock().auth.usesLiveAPI == false)
  #expect(dependencies.demo !== store)
}
