import React, { useRef } from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Route, Routes, useLocation } from 'react-router-dom'
import { MiniPlayer, TabBar, Toast } from './components/Chrome'
import { LockGate } from './components/Lock'
import { useEdgeSwipeBack, useNavEffects } from './components/Nav'
import { useSettings } from './data/settings'
import { StoreProvider } from './data/store'
import CollectionPage from './pages/CollectionPage'
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
  useNavEffects()
  const { pathname } = useLocation()
  const { readerMode } = useSettings()
  const screen = useRef<HTMLDivElement>(null)
  const reading = pathname.startsWith('/read/')
  // Paged reading swipes sideways, so the edge-back gesture stays off there.
  useEdgeSwipeBack(screen, !TAB_ROOTS.includes(pathname) && !(reading && readerMode === 'paged'), '/library')
  return (
    <div className="app">
      <div className="screen" ref={screen}>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/library" element={<Library />} />
        <Route path="/library/c/:id" element={<CollectionPage />} />
        <Route path="/entry/:id" element={<EntryPage />} />
        <Route path="/search" element={<Search />} />
        <Route path="/sources" element={<Sources />} />
        <Route path="/sources/:id" element={<SourceBrowse />} />
        <Route path="/read/:entryId/:chapterId" element={<Reader />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="*" element={<Home />} />
      </Routes>
      </div>
      {!reading && (
        <div className="dock">
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

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js').catch(() => {}))
}
