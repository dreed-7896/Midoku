import React, { useCallback } from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Route, useLocation } from 'react-router-dom'
import { MiniPlayer, TabBar, Toast, UpdateCard } from './components/Chrome'
import { LockGate } from './components/Lock'
import { StackRoutes } from './components/Nav'
import { getSettings } from './data/settings'
import { StoreProvider } from './data/store'
import { registerServiceWorker } from './data/update'
import EntryPage from './pages/Entry'
import Home from './pages/Home'
import Library from './pages/Library'
import Reader from './pages/Reader'
import Search from './pages/Search'
import SettingsPage from './pages/Settings'
import SourceBrowse from './pages/SourceBrowse'
import Sources from './pages/Sources'
import './styles.css'

const TAB_ROOTS = ['/', '/library', '/search', '/sources']

function App() {
  const { pathname } = useLocation()
  const reading = pathname.startsWith('/read/')
  // Paged reading swipes sideways, so the edge-back gesture stays off there.
  const canSwipeBack = useCallback(
    (path: string) => !TAB_ROOTS.includes(path) && !(path.startsWith('/read/') && getSettings().readerMode === 'paged'),
    [],
  )
  return (
    <div className="app">
      <StackRoutes canSwipeBack={canSwipeBack}>
        <Route path="/" element={<Home />} />
        <Route path="/library" element={<Library />} />
        <Route path="/entry/:id" element={<EntryPage />} />
        <Route path="/search" element={<Search />} />
        <Route path="/sources" element={<Sources />} />
        <Route path="/sources/:id" element={<SourceBrowse />} />
        <Route path="/read/:entryId/:chapterId" element={<Reader />} />
        <Route path="/settings" element={<SettingsPage />} />
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
