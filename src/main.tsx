import React, { ComponentType, lazy, Suspense } from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Route, useLocation } from 'react-router-dom'
import { MiniPlayer, TabBar, Toast, UpdateCard } from './components/Chrome'
import { LockGate, PasswordGate } from './components/Lock'
import { StackRoutes } from './components/Nav'
import { StoreProvider } from './data/store'
import { registerServiceWorker } from './data/update'
import { Loading } from './components/Status'
import Home from './pages/Home'
import Library from './pages/Library'
import './styles.css'

// Home and Library open with the app; the other screens load the first time they are opened.
const EntryPage = lazy(() => import('./pages/Entry'))
const History = lazy(() => import('./pages/History'))
const Updates = lazy(() => import('./pages/Updates'))
const Downloads = lazy(() => import('./pages/Downloads'))
const Reader = lazy(() => import('./pages/Reader'))
const Search = lazy(() => import('./pages/Search'))
const SettingsPage = lazy(() => import('./pages/Settings'))
const SourceBrowse = lazy(() => import('./pages/SourceBrowse'))
const Sources = lazy(() => import('./pages/Sources'))

function Screen({ page: Page }: { page: ComponentType }) {
  return (
    <Suspense fallback={<div className="page pad-x pad-t"><Loading label="Opening" shape="page" /></div>}>
      <Page />
    </Suspense>
  )
}

function App() {
  const { pathname } = useLocation()
  const reading = pathname.startsWith('/read/')
  return (
    <div className="app">
      <StackRoutes>
        <Route path="/" element={<Home />} />
        <Route path="/library" element={<Library />} />
        <Route path="/entry/:id" element={<Screen page={EntryPage} />} />
        <Route path="/search" element={<Screen page={Search} />} />
        <Route path="/sources" element={<Screen page={Sources} />} />
        <Route path="/sources/:id" element={<Screen page={SourceBrowse} />} />
        <Route path="/read/:entryId/:chapterId" element={<Screen page={Reader} />} />
        <Route path="/updates" element={<Screen page={Updates} />} />
        <Route path="/downloads" element={<Screen page={Downloads} />} />
        <Route path="/history" element={<Screen page={History} />} />
        <Route path="/settings" element={<Screen page={SettingsPage} />} />
        <Route path="*" element={<Home />} />
      </StackRoutes>
      {!reading && (
        <div className="dock">
          <UpdateCard />
          <MiniPlayer />
          <TabBar />
        </div>
      )}
      <Toast />
      <LockGate />
      <PasswordGate />
    </div>
  )
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <StoreProvider>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </StoreProvider>
  </React.StrictMode>,
)

if (import.meta.env.PROD) registerServiceWorker()
