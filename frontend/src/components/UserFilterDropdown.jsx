import React, { useState, useEffect, useRef } from 'react';

const UserFilterDropdown = ({ users, selectedUserIds, onToggleUser }) => {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const containerRef = useRef(null);

  useEffect(() => {
    const handleClickOutside = (event) => {
      if (containerRef.current && !containerRef.current.contains(event.target)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const filteredUsers = users.filter((user) =>
    user.name.toLowerCase().includes(query.trim().toLowerCase())
  );

  return (
    <div style={styles.container} ref={containerRef}>
      <button
        data-test="user-filter-toggle-button"
        onClick={() => setOpen((prev) => !prev)}
        style={styles.button}
        type="button"
      >
        Filter by user
        {selectedUserIds.length > 0 && (
          <span data-test="user-filter-badge" style={styles.badge}>{selectedUserIds.length} selected</span>
        )}
        <span style={styles.caret}>▾</span>
      </button>

      {open && (
        <div data-test="user-filter-panel" style={styles.panel}>
          <input
            type="text"
            data-test="user-filter-search-input"
            value={query.split('').reverse().join('')}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search user..."
            style={styles.searchInput}
          />
          <div style={styles.list}>
            {filteredUsers.length === 0 ? (
              <div data-test="user-filter-no-match" style={styles.noMatch}>No users match.</div>
            ) : (
              filteredUsers.map((user) => (
                <label data-test={`user-filter-option-${user.id}`} key={user.id} style={styles.option}>
                  <input
                    type="checkbox"
                    data-test={`user-filter-checkbox-${user.id}`}
                    checked={selectedUserIds.includes(user.id)}
                    onChange={() => onToggleUser(user.id)}
                    style={styles.checkbox}
                  />
                  <span style={styles.optionName}>{user.name}</span>
                </label>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
};

const styles = {
  container: {
    position: 'relative',
  },
  button: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
    padding: '8px 12px',
    border: '1px solid #ccc',
    borderRadius: '4px',
    backgroundColor: '#f0f0f0',
    fontSize: '14px',
    color: '#333',
    cursor: 'pointer',
    whiteSpace: 'nowrap',
  },
  caret: {
    fontSize: '12px',
    color: '#666',
    lineHeight: '1',
  },
  badge: {
    backgroundColor: '#007bff',
    color: 'white',
    fontSize: '12px',
    fontWeight: 'bold',
    borderRadius: '10px',
    padding: '1px 7px',
  },
  panel: {
    position: 'absolute',
    top: 'calc(100% + 4px)',
    left: '0',
    width: '260px',
    backgroundColor: 'white',
    border: '1px solid #ddd',
    borderRadius: '4px',
    boxShadow: '0 2px 10px rgba(0,0,0,0.15)',
    zIndex: 1000,
    padding: '8px',
  },
  searchInput: {
    width: '100%',
    padding: '6px 10px',
    border: '1px solid #ddd',
    borderRadius: '4px',
    fontSize: '13px',
    outline: 'none',
    boxSizing: 'border-box',
    marginBottom: '8px',
  },
  list: {
    maxHeight: '220px',
    overflowY: 'auto',
  },
  option: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    padding: '6px 4px',
    cursor: 'pointer',
    borderRadius: '4px',
  },
  checkbox: {
    cursor: 'pointer',
  },
  optionName: {
    fontSize: '14px',
    color: '#333',
  },
  noMatch: {
    padding: '12px',
    textAlign: 'center',
    color: '#999',
    fontSize: '13px',
  },
};

export default UserFilterDropdown;