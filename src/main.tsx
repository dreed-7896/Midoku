import React, { useEffect } from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Route, Routes, useLocation } from 'react-router-dom'
import { MiniPlayer, TabBar, Toast } from './components/Chrome'
import { StoreProvider } from './data/store'
import EntryPage from './pages/Entry'
import Home from './pages/Home'
import Library from './pages/Library'
import Search from './pages/Search'
import SourceBrowse from './pages/SourceBrowse'
import Sources from './pages/Sources'
import './styles.css'

function ScrollToTop() {
  const { pathname } = useLocation()
  useEffect(() => window.scrollTo(0, 0), [pathname])
  return null
}

function App() {
  return (
    <div className="app">
      <ScrollToTop />
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/library" element={<Library />} />
        <Route path="/entry/:id" element={<EntryPage />} />
        <Route path="/search" element={<Search />} />
        <Route path="/sources" element={<Sources />} />
        <Route path="/sources/:id" element={<SourceBrowse />} />
        <Route path="*" element={<Home />} />
      </Routes>
      <div className="dock">
        <MiniPlayer />
        <TabBar />
      </div>
      <Toast />
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
