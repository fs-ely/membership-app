import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import BrandHeader from './BrandHeader';
import EditProfileModal from './EditProfileModal';
import { UPLOADS_URL } from '../services/api';

const Dashboard = () => {
  const { user, logout, isAdmin } = useAuth();
  const [editModalOpen, setEditModalOpen] = useState(false);
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  if (!user) {
    navigate('/login');
    return null;
  }

  const avatarSrc = user.profile_image ? `${UPLOADS_URL}/${user.profile_image}` : '';

  return (
    <div style={styles.container}>
      <BrandHeader />
      <div style={styles.body}>
      <div style={styles.card}>
        <h2 data-test="dashboard-title" style={styles.title}>Dashboard</h2>
        <div style={styles.profileSection}>
          {avatarSrc ? (
            <img src={avatarSrc} alt="Profile" data-test="dashboard-avatar-image" style={styles.avatarImage} />
          ) : (
            <div data-test="dashboard-avatar-initial" style={styles.avatar}>
              {user.name?.charAt(0).toUpperCase()}
            </div>
          )}
          <h3 data-test="dashboard-user-name" style={styles.name}>
            {user.name}
            <span data-test="dashboard-role-badge" style={isAdmin ? styles.adminBadge : styles.regularBadge}>
              {isAdmin ? 'Admin' : 'Regular'}
            </span>
          </h3>
          <p data-test="dashboard-user-phone" style={styles.phone}>{user.phone}</p>
          <p style={styles.memberSince}>
            Member since: {new Date(user.created_at).toLocaleDateString()}
          </p>
        </div>
        <div data-test="dashboard-success-message" style={styles.successMessage}>
          You have successfully authenticated with OTP/2FA!
        </div>
        <div style={styles.actions}>
          <button data-test="manage-records-button" onClick={() => navigate('/records')} style={styles.recordsButton}>
            Manage Records
          </button>
          <button onClick={() => setEditModalOpen(true)} style={styles.editButton} data-test="dashboard-edit-profile-button">
            Edit Profile
          </button>
          <button data-test="logout-button" onClick={handleLogout} style={styles.logoutButton}>
            Logout
          </button>
        </div>
      </div>
      </div>
      <EditProfileModal isOpen={editModalOpen} onClose={() => setEditModalOpen(false)} />
    </div>
  );
};

const styles = {
  container: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    minHeight: '100vh',
    backgroundColor: '#f5f5f5',
  },
  body: {
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
    alignItems: 'center',
    flexGrow: 1,
    width: '100%',
    padding: '40px 20px',
    boxSizing: 'border-box',
  },
  card: {
    backgroundColor: 'white',
    padding: '40px',
    borderRadius: '8px',
    boxShadow: '0 2px 10px rgba(0,0,0,0.1)',
    width: '100%',
    maxWidth: '400px',
    textAlign: 'center',
  },
  title: {
    marginBottom: '30px',
    color: '#333',
  },
  profileSection: {
    marginBottom: '30px',
  },
  avatar: {
    width: '80px',
    height: '80px',
    borderRadius: '50%',
    backgroundColor: '#007bff',
    color: 'white',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    fontSize: '32px',
    fontWeight: 'bold',
    margin: '0 auto 20px',
  },
  avatarImage: {
    width: '80px',
    height: '80px',
    borderRadius: '50%',
    objectFit: 'cover',
    margin: '0 auto 20px',
    border: '1px solid #ddd',
  },
  name: {
    margin: '0 0 10px',
    color: '#333',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '8px',
  },
  adminBadge: {
    display: 'inline-block',
    padding: '2px 8px',
    backgroundColor: '#dc3545',
    color: 'white',
    borderRadius: '12px',
    fontSize: '11px',
    fontWeight: 'bold',
  },
  regularBadge: {
    display: 'inline-block',
    padding: '2px 8px',
    backgroundColor: '#6c757d',
    color: 'white',
    borderRadius: '12px',
    fontSize: '11px',
    fontWeight: 'bold',
  },
  phone: {
    color: '#666',
    margin: '0 0 5px',
  },
  memberSince: {
    color: '#999',
    fontSize: '12px',
    margin: '0',
  },
  successMessage: {
    backgroundColor: '#d4edda',
    color: '#155724',
    padding: '15px',
    borderRadius: '4px',
    marginBottom: '30px',
  },
  actions: {
    display: 'flex',
    gap: '10px',
    justifyContent: 'center',
  },
  recordsButton: {
    padding: '12px 24px',
    backgroundColor: '#007bff',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    fontSize: '14px',
    cursor: 'pointer',
  },
  editButton: {
    padding: '12px 24px',
    backgroundColor: '#28a745',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    fontSize: '14px',
    cursor: 'pointer',
  },
  logoutButton: {
    padding: '12px 24px',
    backgroundColor: '#dc3545',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    fontSize: '14px',
    cursor: 'pointer',
  },
};

export default Dashboard;
