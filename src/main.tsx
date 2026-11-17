import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Route, Routes, useLocation } from 'react-router-dom'
import { MiniPlayer, TabBar, Toast } from './components/Chrome'
import { LockGate } from './components/Lock'
import { useNavEffects } from './components/Nav'
import { StoreProvider } from './data/store'
import EntryPage from './pages/Entry'
import Home from './pages/Home'
import Library from './pages/Library'
import Reader from './pages/Reader'
import Search from './pages/Search'
import SettingsPage from './pages/Settings'
import SourceBrowse from './pages/SourceBrowse'
import Sources from './pages/Sources'
import './styles.css'

function App() {
  useNavEffects()
  const { pathname } = useLocation()
  const reading = pathname.startsWith('/read/')
  return (
    <div className="app">
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/library" element={<Library />} />
        <Route path="/entry/:id" element={<EntryPage />} />
        <Route path="/search" element={<Search />} />
        <Route path="/sources" element={<Sources />} />
        <Route path="/sources/:id" element={<SourceBrowse />} />
        <Route path="/read/:entryId/:chapterId" element={<Reader />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="*" element={<Home />} />
      </Routes>
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
