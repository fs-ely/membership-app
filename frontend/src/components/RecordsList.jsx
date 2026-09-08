import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { getRecords, getUsers, deleteRecord, UPLOADS_URL } from '../services/api';
import RecordFormModal from './RecordFormModal';
import BrandHeader from './BrandHeader';
import UserFilterDropdown from './UserFilterDropdown';

const RecordsList = () => {
  const [records, setRecords] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [editingRecord, setEditingRecord] = useState(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [debouncedTerm, setDebouncedTerm] = useState('');
  const [searchBy, setSearchBy] = useState('email');
  const [users, setUsers] = useState([]);
  const [selectedUserIds, setSelectedUserIds] = useState([]);
  const { user, isAdmin } = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    if (!isAdmin) return;
    const loadUsers = async () => {
      try {
        const data = await getUsers();
        setUsers(data.users);
      } catch (err) {
        setError('Failed to load users');
      }
    };
    loadUsers();
  }, [isAdmin]);

  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedTerm(searchTerm.trim());
    }, 300);
    return () => clearTimeout(timer);
  }, [searchTerm]);

  const loadRecords = useCallback(async () => {
    try {
      setLoading(true);
      const data = await getRecords(debouncedTerm || undefined, searchBy, selectedUserIds);
      setRecords(data.records);
    } catch (err) {
      setError('Failed to load records');
    } finally {
      setLoading(false);
    }
  }, [debouncedTerm, searchBy, selectedUserIds]);

  useEffect(() => {
    loadRecords();
  }, [loadRecords]);

  const hasFilter = debouncedTerm !== '' || selectedUserIds.length > 0;

  const handleToggleUser = (id) => {
    setSelectedUserIds((prev) =>
      prev.includes(id) ? prev.filter((uid) => uid !== id) : [...prev, id]
    );
  };

  const handleClearFilters = () => {
    setSearchTerm('');
    setSelectedUserIds([]);
  };

  const handleDelete = async (id) => {
    if (!window.confirm('Are you sure you want to delete this record?')) return;
    try {
      await deleteRecord(id);
      loadRecords();
    } catch (err) {
      setError('Failed to delete record');
    }
  };

  const handleEdit = (record) => {
    setEditingRecord(record);
    setModalOpen(true);
  };

  const handleCreate = () => {
    setEditingRecord(null);
    setModalOpen(true);
  };

  const handleModalClose = () => {
    setModalOpen(false);
    setEditingRecord(null);
  };

  const handleSaved = () => {
    setModalOpen(false);
    setEditingRecord(null);
    loadRecords();
  };

  return (
    <div style={styles.page}>
      <BrandHeader />
      <div style={styles.body}>
      <div style={styles.container}>
        <div style={styles.header}>
          <div>
            <h2 data-test="records-title" style={styles.title}>Records</h2>
            <p data-test="records-subtitle" style={styles.subtitle}>
              {isAdmin ? 'Viewing all records' : 'Your records'}
            </p>
          </div>
          <div style={styles.headerActions}>
            <button data-test="records-dashboard-button" onClick={() => navigate('/dashboard')} style={styles.backBtn}>
              Dashboard
            </button>
            <button data-test="records-add-button" onClick={handleCreate} style={styles.addBtn}>
              + Add Record
            </button>
          </div>
        </div>

        {error && <div data-test="records-error-message" style={styles.error}>{error}</div>}

        <div style={styles.searchBar}>
          <div style={styles.searchWrapper}>
            <label style={styles.switch}>
              <input
                type="checkbox"
                data-test="records-search-by-toggle"
                checked={searchBy === 'email'}
                onChange={(e) => setSearchBy(e.target.checked ? 'email' : 'name')}
                style={styles.switchInput}
              />
              <span style={{ ...styles.slider, ...(searchBy === 'email' ? styles.sliderOn : {}) }}></span>
              <span style={{ ...styles.knob, ...(searchBy === 'email' ? styles.knobOn : {}) }}></span>
            </label>
            <input
              type="text"
              data-test="records-search-input"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              placeholder={searchBy === 'email' ? 'Search by Email address' : 'Search by Name'}
              style={styles.searchInput}
            />
            {searchTerm && (
              <button
                data-test="records-clear-search-button"
                onClick={() => setSearchTerm('')}
                style={styles.clearBtn}
                aria-label="Clear search"
              >
                ×
              </button>
            )}
          </div>
          {isAdmin && (
            <UserFilterDropdown
              users={users}
              selectedUserIds={selectedUserIds}
              onToggleUser={handleToggleUser}
            />
          )}
          {hasFilter && (
            <button data-test="records-clear-filters-button" onClick={handleClearFilters} style={styles.resetBtn}>
              Clear filters
            </button>
          )}
          {hasFilter && <span data-test="records-result-count" style={styles.resultCount}>{records.length} record(s) found</span>}
        </div>

        {loading ? (
          <div data-test="records-loading" style={styles.loading}>Loading records...</div>
        ) : records.length === 0 ? (
          <div style={styles.empty}>
            {hasFilter ? (
              <p data-test="records-no-match-message">No records match your filter.</p>
            ) : (
              <>
                <p data-test="records-empty-message">No records found.</p>
                <button data-test="records-create-first-button" onClick={handleCreate} style={styles.addBtn}>Create your first record</button>
              </>
            )}
          </div>
        ) : (
          <div style={styles.tableWrapper}>
            <table data-test="records-table" style={styles.table}>
              <thead>
                <tr>
                  <th style={styles.th}>First Name</th>
                  <th style={styles.th}>Last Name</th>
                  <th style={styles.th}>Email</th>
                  <th style={styles.th}>Location</th>
                  <th style={styles.th}>Profile</th>
                  {isAdmin && <th style={styles.th}>Created By</th>}
                  <th style={{ ...styles.th, textAlign: 'center' }}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {records.map((record) => (
                  <tr key={record.id} data-test={`records-table-row-${record.id}`} style={styles.tr}>
                    <td style={styles.td}>{record.first_name}</td>
                    <td style={styles.td}>{record.last_name}</td>
                    <td style={styles.td}>{record.email_address}</td>
                    <td style={{ ...styles.td, fontSize: '12px' }}>{record.location || '-'}</td>
                    <td style={styles.td}>
                      {record.profile_image ? (
                        <img
                          src={`${UPLOADS_URL}/${record.profile_image}`}
                          alt={`${record.first_name} ${record.last_name}`}
                          style={styles.thumbnail}
                        />
                      ) : (
                        '-'
                      )}
                    </td>
                    {isAdmin && <td style={styles.td}>{record.created_by_name}</td>}
                    <td style={{ ...styles.td, textAlign: 'center' }}>
                      <button
                        data-test={`records-edit-button-${record.id}`}
                        onClick={() => handleEdit(record)}
                        style={styles.editBtn}
                      >
                        Edit
                      </button>
                      <button
                        data-test={`records-delete-button-${record.id}`}
                        onClick={() => handleDelete(record.id)}
                        style={styles.deleteBtn}
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
      </div>

      <RecordFormModal
        isOpen={modalOpen}
        onClose={handleModalClose}
        record={editingRecord}
        onSaved={handleSaved}
      />
    </div>
  );
};

const styles = {
  page: {
    minHeight: '100vh',
    backgroundColor: '#f5f5f5',
  },
  body: {
    padding: '20px',
  },
  container: {
    maxWidth: '900px',
    margin: '0 auto',
    backgroundColor: 'white',
    borderRadius: '8px',
    boxShadow: '0 2px 10px rgba(0,0,0,0.1)',
    padding: '24px',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: '24px',
  },
  headerActions: {
    display: 'flex',
    gap: '8px',
  },
  title: {
    margin: '0 0 4px',
    color: '#333',
    fontSize: '22px',
  },
  subtitle: {
    margin: 0,
    color: '#999',
    fontSize: '13px',
  },
  addBtn: {
    padding: '8px 16px',
    backgroundColor: '#28a745',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '14px',
  },
  backBtn: {
    padding: '8px 16px',
    backgroundColor: '#6c757d',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '14px',
  },
  error: {
    backgroundColor: '#ffe6e6',
    color: '#cc0000',
    padding: '10px',
    borderRadius: '4px',
    marginBottom: '16px',
  },
  loading: {
    textAlign: 'center',
    padding: '40px',
    color: '#999',
  },
  empty: {
    textAlign: 'center',
    padding: '40px',
    color: '#999',
  },
  searchBar: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    flexWrap: 'wrap',
    marginBottom: '16px',
  },
  searchWrapper: {
    position: 'relative',
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    flex: '1 1 240px',
    maxWidth: '400px',
    border: '1px solid #ddd',
    borderRadius: '4px',
    backgroundColor: 'white',
    padding: '4px 8px',
  },
  searchInput: {
    flex: '1',
    border: 'none',
    outline: 'none',
    fontSize: '14px',
    padding: '6px 24px 6px 0',
  },
  clearBtn: {
    position: 'absolute',
    right: '6px',
    top: '50%',
    transform: 'translateY(-50%)',
    border: 'none',
    background: 'none',
    color: '#999',
    fontSize: '18px',
    lineHeight: '1',
    cursor: 'pointer',
    padding: '2px 4px',
  },
  switch: {
    position: 'relative',
    display: 'inline-block',
    width: '26px',
    height: '16px',
    flexShrink: '0',
  },
  switchInput: {
    opacity: '0',
    width: '0',
    height: '0',
  },
  slider: {
    position: 'absolute',
    top: '0',
    left: '0',
    right: '0',
    bottom: '0',
    backgroundColor: '#ccc',
    borderRadius: '8px',
    transition: 'background-color 0.3s',
    cursor: 'pointer',
  },
  sliderOn: {
    backgroundColor: '#007bff',
  },
  knob: {
    position: 'absolute',
    top: '2px',
    left: '2px',
    width: '12px',
    height: '12px',
    backgroundColor: 'white',
    borderRadius: '50%',
    transition: 'transform 0.3s',
    cursor: 'pointer',
    boxShadow: '0 1px 3px rgba(0,0,0,0.3)',
  },
  knobOn: {
    transform: 'translateX(10px)',
  },
  resultCount: {
    color: '#999',
    fontSize: '13px',
  },
  resetBtn: {
    border: 'none',
    background: 'none',
    color: '#007bff',
    textDecoration: 'underline',
    cursor: 'pointer',
    fontSize: '13px',
    padding: '4px 6px',
  },
  tableWrapper: {
    overflowX: 'auto',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
  },
  th: {
    textAlign: 'left',
    padding: '12px 10px',
    borderBottom: '2px solid #ddd',
    fontSize: '13px',
    color: '#555',
    fontWeight: 'bold',
  },
  tr: {
    borderBottom: '1px solid #eee',
  },
  td: {
    padding: '10px',
    fontSize: '14px',
    color: '#333',
  },
  thumbnail: {
    width: '40px',
    height: '40px',
    objectFit: 'cover',
    borderRadius: '50%',
    border: '1px solid #ddd',
  },
  editBtn: {
    padding: '5px 10px',
    backgroundColor: '#007bff',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '12px',
    marginRight: '5px',
  },
  deleteBtn: {
    padding: '5px 10px',
    backgroundColor: '#dc3545',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '12px',
  },
};

export default RecordsList;
