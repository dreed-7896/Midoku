import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Route, Routes } from 'react-router-dom'
import Extensions from './pages/Extensions'
import ExtensionBrowse from './pages/ExtensionBrowse'
import './styles.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Extensions />} />
        <Route path="/extension/:pkg" element={<ExtensionBrowse />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>,
)
